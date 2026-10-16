/* ======================================================================================
 * @description : 물류 시스템의 출고 제한 통보(IF-001) 접수 — 요청 검증 · 멱등 접수 · 응답 생성
 * @testClass   : SupplyRestrictionRestResourceTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.16   Kai        Created     최초 작성 — 검증 400 · 신규 접수 201 · 같은 상관 ID 재전송 200
 * ======================================================================================
 *  @see         : SupplyRestrictionRestResource.cls, 인터페이스 정의서 V1.1 IF-001
 *  @note        : 가상 물류 시스템(hankki-logistics org) 소스다. kai-dev에는 배포하지 않는다.
 *                 접근 모드: SOQL은 WITH USER_MODE, DML은 as user로 명시한다. API 67.0은 지정하지 않아도
 *                 user mode로 동작하지만 기본값에 기대지 않는다. 실제 권한은 호출자인 연동 사용자의 권한 집합
 *                 「출고 제한 수신」(Apex 클래스 접근 · 객체 권한 · FLS)이 정하고, 레코드 범위는 with sharing이 정한다
 * ======================================================================================*/
public with sharing class SupplyRestrictionService {
  public static final String HEADER_CORRELATION_ID = 'X-Correlation-Id';
  public static final String STATUS_RECEIVED = '접수';
  public static final String STATUS_APPLIED = '반영완료';
  public static final String STATUS_REJECTED = '반영거절';
  public static final String CALLBACK_NOT_SENT = '미전송';

  private static final Integer HTTP_OK = 200;
  private static final Integer HTTP_CREATED = 201;
  private static final Integer HTTP_BAD_REQUEST = 400;
  // NOTE: 길이 상한은 필드 길이와 같다. 넘는 값을 insert하면 STRING_TOO_LONG으로 500이 되므로 400으로 먼저 거절한다
  private static final Integer CORRELATION_ID_LENGTH = 18;
  private static final Integer STORE_CODE_MAX_LENGTH = 20;
  private static final Integer REASON_MAX_LENGTH = 2000;
  private static final Pattern ISO_DATE = Pattern.compile(
    '(\\d{4})-(\\d{2})-(\\d{2})'
  );

  // NOTE: 응답 status는 영문 코드다. 송신 측(kai-dev)이 이 값으로 물류 통보 상태를 정하므로 화면 값(한글)과 분리한다
  private static final Map<String, String> RESPONSE_STATUS_BY_STATUS = new Map<String, String>{
    STATUS_RECEIVED => 'RECEIVED',
    STATUS_APPLIED => 'APPLIED',
    STATUS_REJECTED => 'REJECTED'
  };

  /**
   * @description : 접수 결과. SupplyRestrictionRestResource가 그대로 HTTP 응답으로 옮긴다.
   **/
  public class ReceiveResult {
    public Integer statusCode;
    public String requestNo;
    public String status;
    public String error;

    public String toJson() {
      if (error != null) {
        return JSON.serialize(new Map<String, Object>{ 'error' => error });
      }
      return JSON.serialize(
        new Map<String, Object>{ 'requestNo' => requestNo, 'status' => status }
      );
    }
  }

  /**
   * @description : 출고 제한 통보를 접수한다. 같은 상관 ID는 한 번만 저장하고, 재전송에는 기존 접수번호를 돌려준다.
   * @author      : 이은석(Kai) | 2026.10.16
   * @param correlationId X-Correlation-Id 헤더 값 (송신 측 페널티 Id, 18자)
   * @param requestBody   JSON 본문 {storeCode, startDate, endDate, reason}
   * @return ReceiveResult 201 신규 접수 · 200 재전송 · 400 검증 실패
   **/
  public static ReceiveResult receive(
    String correlationId,
    String requestBody
  ) {
    List<String> problems = new List<String>();
    SupplyRestriction__c restriction = toRecord(
      correlationId,
      requestBody,
      problems
    );
    if (!problems.isEmpty()) {
      return badRequest('요청 검증 실패: ' + String.join(problems, ', '));
    }
    // DESC: 멱등성 — 같은 키가 이미 있으면 본문이 달라도 바꾸지 않고 기존 접수번호를 돌려준다.
    //       송신 측은 시간 초과처럼 "갔는지 모르는" 실패 뒤에 같은 키로 다시 보낸다
    SupplyRestriction__c existing = findByCorrelationId(
      restriction.CorrelationId__c
    );
    if (existing != null) {
      return accepted(HTTP_OK, existing);
    }
    return insertOrFindExisting(restriction);
  }

  // DESC: 조회와 insert 사이에 같은 키가 먼저 저장될 수 있다(동시 재전송). Unique 제약이 두 번째 insert를 막으면
  //       다시 조회해 200으로 돌려준다 — 출고 제한이 두 건 생기면 제한 기간이 겹친다
  @TestVisible
  private static ReceiveResult insertOrFindExisting(
    SupplyRestriction__c restriction
  ) {
    try {
      insert as user restriction;
    } catch (DmlException e) {
      if (e.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
        throw e;
      }
      return accepted(
        HTTP_OK,
        findByCorrelationId(restriction.CorrelationId__c)
      );
    }
    return accepted(
      HTTP_CREATED,
      findByCorrelationId(restriction.CorrelationId__c)
    );
  }

  // DESC: 문제를 하나에서 멈추지 않고 모두 모은다 — 송신 측이 한 번에 고칠 수 있게
  private static SupplyRestriction__c toRecord(
    String correlationId,
    String requestBody,
    List<String> problems
  ) {
    if (
      String.isBlank(correlationId) ||
      correlationId.length() != CORRELATION_ID_LENGTH
    ) {
      problems.add(
        HEADER_CORRELATION_ID + ' 헤더는 ' + CORRELATION_ID_LENGTH + '자'
      );
    }
    Map<String, Object> payload = parseObject(requestBody);
    if (payload == null) {
      problems.add('본문이 JSON 객체가 아님');
      return null;
    }
    String storeCode = readText(
      payload,
      'storeCode',
      STORE_CODE_MAX_LENGTH,
      true,
      problems
    );
    Date startDate = readDate(payload, 'startDate', problems);
    Date endDate = readDate(payload, 'endDate', problems);
    String reason = readText(
      payload,
      'reason',
      REASON_MAX_LENGTH,
      false,
      problems
    );
    if (startDate != null && endDate != null && startDate > endDate) {
      problems.add('startDate가 endDate보다 늦음');
    }
    return new SupplyRestriction__c(
      CorrelationId__c = correlationId,
      StoreCode__c = storeCode,
      StartDate__c = startDate,
      EndDate__c = endDate,
      Reason__c = reason,
      // NOTE: 선택 목록 기본값이 채워지기를 기대하지 않고 시작 상태를 명시한다
      Status__c = STATUS_RECEIVED,
      CallbackStatus__c = CALLBACK_NOT_SENT
    );
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

  // DESC: 문자열이 아니면 형식 오류로 본다 — 매장코드 "0012"가 숫자 12로 오면 다른 매장이 된다
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

  // DESC: yyyy-MM-dd만 받는다. 2026-02-30처럼 없는 날짜는 다음 달로 넘기지 않고 거절한다
  private static Date readDate(
    Map<String, Object> payload,
    String key,
    List<String> problems
  ) {
    Object value = payload.get(key);
    if (isBlank(value)) {
      problems.add(key + ' 누락');
      return null;
    }
    Matcher parts = value instanceof String
      ? ISO_DATE.matcher((String) value)
      : null;
    if (parts == null || !parts.matches()) {
      problems.add(key + ' 형식 오류(yyyy-MM-dd)');
      return null;
    }
    Date parsed = toExistingDate(
      Integer.valueOf(parts.group(1)),
      Integer.valueOf(parts.group(2)),
      Integer.valueOf(parts.group(3))
    );
    if (parsed == null) {
      problems.add(key + ' 없는 날짜');
    }
    return parsed;
  }

  // NOTE: Date.newInstance는 범위를 벗어난 일자를 다음 달로 넘길 수 있어, 만든 뒤 월 · 일이 그대로인지 다시 본다
  private static Date toExistingDate(Integer year, Integer month, Integer day) {
    if (year < 1700 || year > 4000 || month < 1 || month > 12 || day < 1) {
      return null;
    }
    Date candidate = Date.newInstance(year, month, day);
    return candidate.month() == month &&
      candidate.day() == day
      ? candidate
      : null;
  }

  private static Boolean isBlank(Object value) {
    return value == null ||
      (value instanceof String && String.isBlank((String) value));
  }

  private static SupplyRestriction__c findByCorrelationId(
    String correlationId
  ) {
    List<SupplyRestriction__c> restrictions = [
      SELECT Id, Name, Status__c
      FROM SupplyRestriction__c
      WHERE CorrelationId__c = :correlationId
      WITH USER_MODE
      LIMIT 1
    ];
    return restrictions.isEmpty() ? null : restrictions[0];
  }

  private static ReceiveResult accepted(
    Integer statusCode,
    SupplyRestriction__c restriction
  ) {
    ReceiveResult result = new ReceiveResult();
    result.statusCode = statusCode;
    result.requestNo = restriction.Name;
    result.status = RESPONSE_STATUS_BY_STATUS.get(restriction.Status__c);
    return result;
  }

  private static ReceiveResult badRequest(String message) {
    ReceiveResult result = new ReceiveResult();
    result.statusCode = HTTP_BAD_REQUEST;
    result.error = message;
    return result;
  }
}
