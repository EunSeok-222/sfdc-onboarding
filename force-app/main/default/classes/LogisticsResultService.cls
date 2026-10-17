/* ======================================================================================
 * @description : 물류 시스템의 공급 제한 반영 결과 회신(IF-004) 수신 — 요청 검증 · 멱등 판정 · 인터페이스 로그 「수신」 기록
 * @testClass   : LogisticsResultRestResourceTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 기록 200 · 재수신 200 · 400 · 404 · 409, 페널티는 수정하지 않음(Step 7-A)
 * ======================================================================================
 *  @see         : LogisticsResultRestResource.cls, LogisticsNotifyService.cls, 인터페이스 정의서 V1.1 IF-004
 *  @note        : 5R 구조 — 반영 결과는 페널티가 아니라 인터페이스 로그에 「수신」 행으로만 남긴다(승인된 페널티는 수정하지 않는다).
 *                 실행 사용자는 External Client App의 Run As 연동 사용자(「물류 연동 처리」)다.
 *                 판정 순서: 형식(400) → 페널티 존재(404) → 이미 받은 회신(200 UNCHANGED · 409) → 페널티 상태 · IF-001 송신 성공(409) → 기록(200)
 * ======================================================================================*/
public with sharing class LogisticsResultService {
  public static final String INTERFACE_ID = 'IF-004';
  public static final String DIRECTION_INBOUND = '수신';
  public static final String RESULT_APPLIED = '반영완료';
  public static final String RESULT_REJECTED = '반영거절';
  public static final String RESPONSE_RECORDED = 'RECORDED';
  public static final String RESPONSE_UNCHANGED = 'UNCHANGED';

  private static final Integer HTTP_OK = 200;
  private static final Integer HTTP_BAD_REQUEST = 400;
  private static final Integer HTTP_NOT_FOUND = 404;
  private static final Integer HTTP_CONFLICT = 409;
  private static final Integer HTTP_SERVER_ERROR = 500;

  // NOTE: 길이 상한은 필드 길이와 같다. 넘는 값을 insert하면 STRING_TOO_LONG으로 500이 되므로 400으로 먼저 거절한다
  private static final Integer CORRELATION_ID_LENGTH = 18;
  private static final Integer REQUEST_NO_MAX_LENGTH = 20;
  private static final Integer MESSAGE_MAX_LENGTH = 255;
  private static final Integer BODY_MAX_LENGTH = 32768;

  // NOTE: 요청 status(영문 코드) → 반영 결과(화면 값). 물류 org가 IF-001 응답 status에 쓰는 코드와 같다
  private static final Map<String, String> RESULT_BY_STATUS = new Map<String, String>{
    'APPLIED' => RESULT_APPLIED,
    'REJECTED' => RESULT_REJECTED
  };
  // NOTE: ISO-8601 UTC 또는 오프셋 표기(예: 2026-10-16T01:00:00Z, 2026-10-16T10:00:00.000+09:00)
  private static final Pattern ISO_DATETIME = Pattern.compile(
    '\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,3})?(Z|[+-]\\d{2}:\\d{2})'
  );

  // NOTE: 테스트에서만 켠다 — 수신 로그 insert 직후 예외를 내 진입점의 500 응답과 롤백(로그가 남지 않음)을 검증한다.
  //       운영에서는 항상 false라 동작이 바뀌지 않는다
  @TestVisible
  private static Boolean failAfterInsertForTest = false;

  private class SimulatedFailureException extends Exception {
  }

  /**
   * @description : 수신 결과. LogisticsResultRestResource가 그대로 HTTP 응답으로 옮긴다.
   **/
  public class ReceiveResult {
    public Integer statusCode;
    public String result;
    public String logNo;
    public String error;

    public String toJson() {
      if (error != null) {
        return JSON.serialize(new Map<String, Object>{ 'error' => error });
      }
      return JSON.serialize(
        new Map<String, Object>{ 'result' => result, 'logNo' => logNo }
      );
    }
  }

  // DESC: 검증을 통과한 요청 값
  private class ResultRequest {
    Id penaltyId;
    String requestNo;
    String applyResult;
  }

  /**
   * @description : 반영 결과 회신을 받아 인터페이스 로그에 「수신」 행을 남긴다. 같은 회신의 재전송은 기록하지 않고 200으로 답한다.
   *                페널티는 어떤 경우에도 수정하지 않는다.
   * @author      : 이은석(Kai) | 2026.10.18
   * @param requestBody JSON 본문 {correlationId, requestNo, status, processedAt, message}
   * @return ReceiveResult 200 RECORDED · 200 UNCHANGED · 400 형식 오류 · 404 페널티 없음 · 409 상태 불일치 · 다른 결과로 이미 수신
   **/
  public static ReceiveResult receive(String requestBody) {
    List<String> problems = new List<String>();
    ResultRequest request = parse(requestBody, problems);
    if (!problems.isEmpty()) {
      return failure(
        HTTP_BAD_REQUEST,
        '요청 검증 실패: ' + String.join(problems, ', ')
      );
    }

    ResultStore store = new ResultStore();
    Penalty__c penalty = store.lockPenalty(request.penaltyId);
    if (penalty == null) {
      return failure(HTTP_NOT_FOUND, '페널티 없음: ' + request.penaltyId);
    }

    // DESC: 멱등성 판정을 상태 검사보다 먼저 한다 — 기록 뒤에 페널티 상태가 바뀌어도 같은 회신의 재전송에는 같은 답을 준다.
    //       물류 org는 시간 초과처럼 "갔는지 모르는" 실패 뒤에 같은 회신을 다시 보낸다
    IntegrationLog__c receipt = store.findReceipt(
      penalty.Id,
      request.requestNo
    );
    if (receipt != null) {
      if (receipt.ApplyResult__c == request.applyResult) {
        return recorded(RESPONSE_UNCHANGED, receipt.Name);
      }
      return failure(
        HTTP_CONFLICT,
        '이미 다른 결과로 수신됨: ' +
          receipt.Name +
          ' (' +
          receipt.ApplyResult__c +
          ')'
      );
    }

    String stateProblem = findStateProblem(
      penalty,
      request.requestNo,
      store.findSentRequestNos(penalty.Id)
    );
    if (stateProblem != null) {
      return failure(HTTP_CONFLICT, stateProblem);
    }
    return record(store, penalty, request, requestBody);
  }

  /**
   * @description : 처리 중 예기치 못한 오류의 응답. 오류 상세(클래스 · 줄 번호)는 응답에 싣지 않는다.
   * @author      : 이은석(Kai) | 2026.10.18
   * @return ReceiveResult 500 — 물류 org는 5xx를 재시도한다
   **/
  public static ReceiveResult serverError() {
    return failure(
      HTTP_SERVER_ERROR,
      '처리 중 오류 — 같은 요청을 다시 보내면 됩니다'
    );
  }

  // DESC: 회신은 IF-001로 접수된 건에만 받는다 — 공급 제한 · 승인이 아니거나, 같은 상관 ID · 접수번호로 송신에 성공한 기록이 없으면 거절
  private static String findStateProblem(
    Penalty__c penalty,
    String requestNo,
    Set<String> sentRequestNos
  ) {
    if (
      penalty.PenaltyType__c !=
      LogisticsNotifyService.PENALTY_TYPE_SUPPLY_RESTRICTION ||
      penalty.Status__c != LogisticsNotifyService.PENALTY_STATUS_APPROVED
    ) {
      return '공급 제한 · 승인 상태가 아님 (' +
        penalty.PenaltyType__c +
        ' · ' +
        penalty.Status__c +
        ')';
    }
    if (sentRequestNos.isEmpty()) {
      return 'IF-001 송신 성공 기록 없음';
    }
    // NOTE: 정의서 V1.1은 접수번호 불일치를 400으로 적었지만, 저장된 상태와의 비교라 상태 불일치(409)로 묶었다
    if (!sentRequestNos.contains(requestNo)) {
      return '접수번호가 IF-001 송신 성공 기록과 다름';
    }
    return null;
  }

  // DESC: 로그 insert → 자동 번호(Name) 조회 → 응답 본문(로그 번호 포함)을 같은 로그에 기록. 페널티는 건드리지 않는다
  // WARN: 헤더(Authorization 등)는 기록하지 않는다 — 요청은 본문만 남긴다
  private static ReceiveResult record(
    ResultStore store,
    Penalty__c penalty,
    ResultRequest request,
    String requestBody
  ) {
    IntegrationLog__c log = new IntegrationLog__c(
      Penalty__c = penalty.Id,
      InterfaceId__c = INTERFACE_ID,
      Direction__c = DIRECTION_INBOUND,
      Status__c = LogisticsNotifyService.LOG_STATUS_SUCCESS,
      CorrelationId__c = penalty.Id,
      RequestNo__c = request.requestNo,
      ApplyResult__c = request.applyResult,
      StatusCode__c = HTTP_OK,
      RequestBody__c = requestBody.left(BODY_MAX_LENGTH)
    );
    // NOTE: 소유자 규칙 B안(IF-001 송신 로그와 같음) — 로그를 읽을 수 있는 활성 페널티 소유자, 아니면 기본 소유자(연동 사용자).
    //       알려진 한계: 소유자가 비활성 · 로그 권한 없음이면 수신 행이 연동 사용자 소유라 현장(SV · 권역팀장) 화면에 보이지 않는다
    if (
      LogisticsNotifyService.findLogReaders(new Set<Id>{ penalty.OwnerId })
        .contains(penalty.OwnerId)
    ) {
      log.OwnerId = penalty.OwnerId;
    }
    store.insertReceipt(log);
    if (failAfterInsertForTest) {
      throw new SimulatedFailureException('테스트용 강제 실패');
    }
    ReceiveResult result = recorded(RESPONSE_RECORDED, store.findLogNo(log.Id));
    log.ResponseBody__c = result.toJson();
    store.saveReceipt(log);
    return result;
  }

  // DESC: 문제를 하나에서 멈추지 않고 모두 모은다 — 송신 측이 한 번에 고칠 수 있게
  private static ResultRequest parse(
    String requestBody,
    List<String> problems
  ) {
    Map<String, Object> payload = parseObject(requestBody);
    if (payload == null) {
      problems.add('본문이 JSON 객체가 아님');
      return null;
    }
    ResultRequest request = new ResultRequest();
    request.penaltyId = readPenaltyId(payload, problems);
    request.requestNo = readText(
      payload,
      'requestNo',
      REQUEST_NO_MAX_LENGTH,
      true,
      problems
    );
    Object status = payload.get('status');
    if (
      !(status instanceof String) ||
      !RESULT_BY_STATUS.containsKey((String) status)
    ) {
      problems.add('status는 APPLIED 또는 REJECTED');
    } else {
      request.applyResult = RESULT_BY_STATUS.get((String) status);
    }
    readProcessedAt(payload, problems);
    // DESC: 거절이면 사유가 있어야 사람이 후속 조치를 정한다. 사유는 요청 본문으로 로그에 남는다
    readText(
      payload,
      'message',
      MESSAGE_MAX_LENGTH,
      request.applyResult == RESULT_REJECTED,
      problems
    );
    return request;
  }

  private static Map<String, Object> parseObject(String requestBody) {
    if (String.isBlank(requestBody)) {
      return null;
    }
    try {
      Object parsed = JSON.deserializeUntyped(requestBody);
      return parsed instanceof Map<String, Object>
        ? (Map<String, Object>) parsed
        : null;
    } catch (JSONException e) {
      return null;
    }
  }

  // DESC: 상관 ID = IF-001에서 보낸 페널티 Id 18자. 다른 오브젝트의 Id는 형식 오류로 본다
  private static Id readPenaltyId(
    Map<String, Object> payload,
    List<String> problems
  ) {
    Object value = payload.get('correlationId');
    if (
      !(value instanceof String) ||
      ((String) value).length() != CORRELATION_ID_LENGTH
    ) {
      problems.add('correlationId는 ' + CORRELATION_ID_LENGTH + '자 문자열');
      return null;
    }
    try {
      Id penaltyId = Id.valueOf((String) value);
      if (penaltyId.getSObjectType() == Penalty__c.SObjectType) {
        return penaltyId;
      }
    } catch (StringException e) {
      // NOTE: Id 형식이 아니면 Id.valueOf가 StringException을 던진다 — 아래에서 형식 오류로 모은다
    }
    problems.add('correlationId가 페널티 Id가 아님');
    return null;
  }

  // DESC: 형식만 확인한다. 값은 요청 본문으로 로그에 남는다
  private static void readProcessedAt(
    Map<String, Object> payload,
    List<String> problems
  ) {
    Object value = payload.get('processedAt');
    if (isBlank(value)) {
      problems.add('processedAt 누락');
      return;
    }
    if (
      !(value instanceof String) ||
      !ISO_DATETIME.matcher((String) value).matches() ||
      !isDatetime((String) value)
    ) {
      problems.add('processedAt 형식 오류(ISO-8601)');
    }
  }

  // NOTE: 패턴이 맞아도 13월 · 25시처럼 없는 일시가 올 수 있어 실제로 해석해 본다
  private static Boolean isDatetime(String value) {
    try {
      JSON.deserialize(JSON.serialize(value), Datetime.class);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  // DESC: 문자열이 아니면 형식 오류로 본다
  private static String readText(
    Map<String, Object> payload,
    String key,
    Integer maxLength,
    Boolean required,
    List<String> problems
  ) {
    Object value = payload.get(key);
    if (isBlank(value)) {
      if (required) {
        problems.add(key + ' 누락');
      }
      return null;
    }
    if (!(value instanceof String)) {
      problems.add(key + ' 문자열 아님');
      return null;
    }
    String text = (String) value;
    if (text.length() > maxLength) {
      problems.add(key + ' ' + maxLength + '자 초과');
      return null;
    }
    return text;
  }

  private static Boolean isBlank(Object value) {
    return value == null ||
      (value instanceof String && String.isBlank((String) value));
  }

  private static ReceiveResult recorded(String outcome, String logNo) {
    ReceiveResult result = new ReceiveResult();
    result.statusCode = HTTP_OK;
    result.result = outcome;
    result.logNo = logNo;
    return result;
  }

  private static ReceiveResult failure(Integer statusCode, String message) {
    ReceiveResult result = new ReceiveResult();
    result.statusCode = statusCode;
    result.error = message;
    return result;
  }

  // WARN: 수신 처리(페널티 조회 · 송신 기록 조회 · 수신 로그 조회 · 기록)만 sharing 예외(without sharing)다.
  //       실행 사용자(연동 사용자)는 역할 · 공유가 없어 비공개(Private) 페널티와 로그를 0건으로 조회한다 — 아웃박스(OutboxStore)와 같은 이유.
  //       범위: Penalty__c는 판정에 필요한 Id · OwnerId · 유형 · 상태만 읽고 수정하지 않는다.
  //       IntegrationLog__c는 IF-001 송신 성공 기록 조회와 IF-004 수신 로그 조회 · 기록만 한다. 다른 로직은 넣지 않는다
  // NOTE: 내부 클래스는 바깥 클래스의 sharing을 물려받지 않으므로 without sharing을 명시한다
  private without sharing class ResultStore {
    // DESC: 페널티 행을 잠가(FOR UPDATE) 같은 건의 회신이 동시에 와도 수신 로그가 두 번 남지 않게 한다.
    //       잠금은 트랜잭션이 끝나면 풀리고 페널티 값은 바꾸지 않는다
    public Penalty__c lockPenalty(Id penaltyId) {
      List<Penalty__c> penalties = [
        SELECT Id, OwnerId, PenaltyType__c, Status__c
        FROM Penalty__c
        WHERE Id = :penaltyId
        WITH SYSTEM_MODE
        LIMIT 1
        FOR UPDATE
      ];
      return penalties.isEmpty() ? null : penalties[0];
    }

    public IntegrationLog__c findReceipt(Id penaltyId, String requestNo) {
      List<IntegrationLog__c> receipts = [
        SELECT Name, ApplyResult__c
        FROM IntegrationLog__c
        WHERE
          InterfaceId__c = :INTERFACE_ID
          AND Direction__c = :DIRECTION_INBOUND
          AND CorrelationId__c = :penaltyId
          AND RequestNo__c = :requestNo
        WITH SYSTEM_MODE
        ORDER BY CreatedDate
        LIMIT 1
      ];
      return receipts.isEmpty() ? null : receipts[0];
    }

    // DESC: 같은 상관 ID로 IF-001 송신에 성공한 기록의 접수번호들
    public Set<String> findSentRequestNos(Id penaltyId) {
      Set<String> requestNos = new Set<String>();
      for (IntegrationLog__c sent : [
        SELECT RequestNo__c
        FROM IntegrationLog__c
        WHERE
          InterfaceId__c = :LogisticsNotifyService.INTERFACE_ID
          AND Direction__c = :LogisticsNotifyService.DIRECTION_OUTBOUND
          AND Status__c = :LogisticsNotifyService.LOG_STATUS_SUCCESS
          AND CorrelationId__c = :penaltyId
        WITH SYSTEM_MODE
      ]) {
        requestNos.add(sent.RequestNo__c);
      }
      return requestNos;
    }

    // DESC: 로그는 시스템 기록이다 — 연동 사용자의 로그 권한 · FLS와 무관하게 as system
    public void insertReceipt(IntegrationLog__c log) {
      insert as system log;
    }

    public String findLogNo(Id logId) {
      return [
        SELECT Name
        FROM IntegrationLog__c
        WHERE Id = :logId
        WITH SYSTEM_MODE
      ]
      .Name;
    }

    public void saveReceipt(IntegrationLog__c log) {
      update as system log;
    }
  }
}
