/* ======================================================================================
 * @description : 공급 제한 페널티 승인 시 물류 시스템에 출고 제한을 통보하는 Outbound 콜아웃 (BR-08 후단, IF-001)
 * @testClass   : LogisticsNotifyServiceTest, LogisticsNotifyQueueableTest, PenaltyTriggerHandlerTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 — 통보 요청 · 상태코드별 재시도 분기 (호출부 연결 없는 스텁)
 *  2026.10.17   Kai        Updated     Outbox 처리 추가 — 승인 시 로그 · 이벤트만 남기고, 연동 사용자 Queueable이 전송 · 재시도
 * ======================================================================================
 *  @see         : LogisticsNotifyQueueable.cls, LogisticsNotifyEventTriggerHandler.cls, 인터페이스 정의서 V1.1 IF-001
 *  @note        : 원칙 — 승인된 페널티는 수정하지 않는다 · 외부 호출은 연동 사용자만 한다 · 모든 연동 상태는 인터페이스 로그에 남긴다.
 *                 승인 트랜잭션(승인자 권한)은 requestNotifications로 로그 「전송대기」와 이벤트만 남기고,
 *                 이벤트 트리거의 실행 사용자(연동 사용자)가 processPendingLogs로 전송 · 재시도한다
 * ======================================================================================*/
public with sharing class LogisticsNotifyService {
  public static final String ENDPOINT = 'callout:HankkiLogistics/v1/supply-restrictions';
  public static final String HEADER_CORRELATION_ID = 'X-Correlation-Id';
  public static final String PENALTY_TYPE_SUPPLY_RESTRICTION = '공급 제한';
  public static final String PENALTY_STATUS_APPROVED = '승인';

  public static final String INTERFACE_ID = 'IF-001';
  public static final String DIRECTION_OUTBOUND = '송신';
  public static final String LOG_STATUS_PENDING = '전송대기';
  public static final String LOG_STATUS_SUCCESS = '성공';
  public static final String LOG_STATUS_RETRY = '재시도대기';
  public static final String LOG_STATUS_FAILED = '실패';
  public static final String LOG_STATUS_ABORTED = '중단';
  private static final Set<String> DUE_STATUSES = new Set<String>{
    LOG_STATUS_PENDING,
    LOG_STATUS_RETRY
  };

  // NOTE: 콜아웃 누적 120초 한도 ÷ 타임아웃 10초 = 한 실행 최대 10건
  @TestVisible
  private static final Integer BATCH_SIZE = 10;
  // NOTE: 최초 1회 + 재시도 3회 = 최대 4번. 재시도 간격 1 → 5 → 10분 — 지연 Queueable 최대 10분 안에 들어오게 정했다
  @TestVisible
  private static final List<Integer> RETRY_DELAY_MINUTES = new List<Integer>{
    1,
    5,
    10
  };
  private static final Integer MESSAGE_MAX_LENGTH = 255;
  private static final Integer BODY_MAX_LENGTH = 32768;

  // NOTE: 플랫폼 기본값도 10초지만 명시한다 — 기본값에 기대면 물류 시스템과 협의한 응답 한도가 코드에 드러나지 않고,
  //       기본값이 바뀌면 동작이 조용히 달라진다. 콜아웃 1건 최대 120초
  private static final Integer TIMEOUT_MS = 10000;
  private static final Integer HTTP_TOO_MANY_REQUESTS = 429;

  /**
   * @description : 물류 통보 실패. 호출자가 재시도 여부를 판단할 수 있게 상태코드와 재시도 가능 여부를 담는다.
   **/
  public class LogisticsNotifyException extends Exception {
    // NOTE: 응답 자체가 없으면(연결 실패 · 시간 초과 · 입력 검증 실패) null
    public Integer statusCode;
    public Boolean retryable;
    public String responseBody;
  }

  /**
   * @description : processPendingLogs 결과. Queueable이 다음 job을 언제 넣을지 정한다.
   **/
  public class ProcessResult {
    /** 이번에 다 못 보낸 처리 대기 로그가 남았는지 (있으면 즉시 다음 job) */
    public Boolean hasMoreDue = false;
    /** 가장 이른 재시도 시각 (없으면 null) */
    public Datetime nextRetryAt;
  }

  /**
   * @description : 승인 트랜잭션(승인자 권한)에서 부른다. 페널티마다 로그 「전송대기」를 남기고 이벤트를 1건 발행한다.
   *                콜아웃 · 페널티 수정 · enqueue는 하지 않는다.
   * @author      : 이은석(Kai) | 2026.10.17
   * @param penalties 공급 제한이 「승인」으로 바뀐 페널티 (Trigger.new — Id · OwnerId 사용)
   **/
  public static void requestNotifications(List<Penalty__c> penalties) {
    if (penalties.isEmpty()) {
      return;
    }
    Set<Id> ownerIds = new Set<Id>();
    for (Penalty__c penalty : penalties) {
      ownerIds.add(penalty.OwnerId);
    }
    Set<Id> logReaderIds = findLogReaders(ownerIds);
    List<IntegrationLog__c> logs = new List<IntegrationLog__c>();
    for (Penalty__c penalty : penalties) {
      IntegrationLog__c log = new IntegrationLog__c(
        Penalty__c = penalty.Id,
        InterfaceId__c = INTERFACE_ID,
        Direction__c = DIRECTION_OUTBOUND,
        Status__c = LOG_STATUS_PENDING,
        CorrelationId__c = penalty.Id,
        AttemptCount__c = 0
      );
      // NOTE: 로그 소유자 = 페널티 소유자 — OWD 비공개에서 SV는 자기 건, 권역팀장은 역할 계층으로 본다
      // WARN: 소유자는 로그 읽기 권한이 있어야 한다(TRANSFER_REQUIRES_READ). 권한 없는 사람을 소유자로 지정하면
      //       승인 트랜잭션 전체가 실패한다 — 기록 때문에 승인이 막히면 안 되므로, 그때는 기본 소유자(insert한 사용자)로 둔다
      if (logReaderIds.contains(penalty.OwnerId)) {
        log.OwnerId = penalty.OwnerId;
      }
      logs.add(log);
    }
    // WARN: 로그는 사용자 행위가 아니라 시스템 기록이다 — 승인자에게 로그 생성 권한이 없어도 남도록 as system
    insert as system logs;
    // DESC: 커밋 후 발행(PublishAfterCommit) — 승인이 롤백되면 이벤트도 나가지 않는다. 건수와 무관하게 1건이면 된다
    EventBus.publish(
      new LogisticsNotifyEvent__e(InterfaceId__c = INTERFACE_ID)
    );
  }

  // DESC: 로그 오브젝트 읽기 권한(프로필 또는 권한 집합)이 있는 사용자만 고른다 — SOQL 1번, 대상 건수와 무관
  // NOTE: 프로필 권한도 프로필 소유 권한 집합의 할당(PermissionSetAssignment)으로 잡힌다.
  //       조회는 승인자가 설정 정보를 볼 권한이 없어도 되도록 시스템 모드
  private static Set<Id> findLogReaders(Set<Id> userIds) {
    Set<Id> readerIds = new Set<Id>();
    for (PermissionSetAssignment assignment : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE
        AssigneeId IN :userIds
        AND PermissionSetId IN (
          SELECT ParentId
          FROM ObjectPermissions
          WHERE SobjectType = 'IntegrationLog__c' AND PermissionsRead = TRUE
        )
      WITH SYSTEM_MODE
    ]) {
      readerIds.add(assignment.AssigneeId);
    }
    return readerIds;
  }

  /**
   * @description : 연동 사용자 권한(Queueable)에서 부른다. 처리할 차례가 된 로그를 최대 10건 보내고 결과를 기록한다.
   *                콜아웃을 모두 끝낸 뒤 로그 update를 1번 한다.
   * @author      : 이은석(Kai) | 2026.10.17
   * @return ProcessResult 남은 처리 대기 여부 · 가장 이른 재시도 시각
   **/
  public static ProcessResult processPendingLogs() {
    Datetime now = Datetime.now();
    Integer fetchSize = BATCH_SIZE + 1;
    // NOTE: 시스템 모드 — 로그 · 페널티 조회는 실행 사용자 FLS와 무관한 시스템 책임이다
    List<IntegrationLog__c> dueLogs = [
      SELECT
        Id,
        AttemptCount__c,
        Penalty__r.Id,
        Penalty__r.PenaltyType__c,
        Penalty__r.Status__c,
        Penalty__r.StartDate__c,
        Penalty__r.EndDate__c,
        Penalty__r.Reason__c,
        Penalty__r.Franchise__r.StoreCode__c
      FROM IntegrationLog__c
      WHERE
        InterfaceId__c = :INTERFACE_ID
        AND Status__c IN :DUE_STATUSES
        AND (NextAttemptAt__c = NULL
        OR NextAttemptAt__c <= :now)
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
      LIMIT :fetchSize
    ];

    ProcessResult result = new ProcessResult();
    result.hasMoreDue = dueLogs.size() > BATCH_SIZE;
    List<IntegrationLog__c> batch = new List<IntegrationLog__c>();
    for (IntegrationLog__c log : dueLogs) {
      if (batch.size() == BATCH_SIZE) {
        break;
      }
      applyAttempt(log, now);
      batch.add(log);
    }
    // WARN: 결과 기록도 시스템 책임 — 실행 사용자(연동 사용자)의 로그 FLS와 무관하게 as system
    update as system batch;
    result.nextRetryAt = findNextRetryAt(now);
    return result;
  }

  // DESC: 한 번 보내고 결과를 로그 필드에 옮긴다. 헤더는 기록하지 않는다
  // WARN: Authorization 헤더 · 토큰은 절대 기록하지 않는다 — 요청은 본문(JSON)만, 응답도 본문만 남긴다
  private static void applyAttempt(IntegrationLog__c log, Datetime now) {
    log.AttemptCount__c =
      (log.AttemptCount__c == null ? 0 : log.AttemptCount__c) + 1;
    Penalty__c penalty = log.Penalty__r;
    if (penalty == null) {
      // NOTE: 페널티가 삭제되면 Lookup이 비워진다(SetNull) — 보낼 대상이 없어 재시도해도 같다
      markFailed(log, null, null, '페널티가 없어 보낼 수 없음');
      return;
    }
    log.RequestBody__c = truncate(buildPayload(penalty), BODY_MAX_LENGTH);
    try {
      HttpResponse res = notifySupplyRestriction(penalty);
      log.Status__c = LOG_STATUS_SUCCESS;
      log.StatusCode__c = res.getStatusCode();
      log.ResponseBody__c = truncate(res.getBody(), BODY_MAX_LENGTH);
      log.RequestNo__c = readRequestNo(res.getBody());
      log.ErrorMessage__c = null;
      log.NextAttemptAt__c = null;
    } catch (LogisticsNotifyException e) {
      if (!e.retryable) {
        markFailed(log, e.statusCode, e.responseBody, e.getMessage());
        return;
      }
      log.StatusCode__c = e.statusCode;
      log.ResponseBody__c = truncate(e.responseBody, BODY_MAX_LENGTH);
      log.ErrorMessage__c = truncate(e.getMessage(), MESSAGE_MAX_LENGTH);
      Integer retriesUsed = log.AttemptCount__c.intValue() - 1;
      if (retriesUsed < RETRY_DELAY_MINUTES.size()) {
        log.Status__c = LOG_STATUS_RETRY;
        log.NextAttemptAt__c = now.addMinutes(RETRY_DELAY_MINUTES[retriesUsed]);
      } else {
        // DESC: 재시도 3회를 다 쓰고도 재시도 대상으로 실패 — 자동으로는 그만두고 사람이 확인한다
        log.Status__c = LOG_STATUS_ABORTED;
        log.NextAttemptAt__c = null;
      }
    }
  }

  private static void markFailed(
    IntegrationLog__c log,
    Integer statusCode,
    String responseBody,
    String message
  ) {
    log.Status__c = LOG_STATUS_FAILED;
    log.StatusCode__c = statusCode;
    log.ResponseBody__c = truncate(responseBody, BODY_MAX_LENGTH);
    log.ErrorMessage__c = truncate(message, MESSAGE_MAX_LENGTH);
    log.NextAttemptAt__c = null;
  }

  // DESC: 이번 실행 뒤 남은 재시도 중 가장 이른 시각 — Queueable이 그때 다시 돌도록 지연 job을 넣는다
  private static Datetime findNextRetryAt(Datetime now) {
    List<IntegrationLog__c> waitingLogs = [
      SELECT NextAttemptAt__c
      FROM IntegrationLog__c
      WHERE
        InterfaceId__c = :INTERFACE_ID
        AND Status__c = :LOG_STATUS_RETRY
        AND NextAttemptAt__c > :now
      WITH SYSTEM_MODE
      ORDER BY NextAttemptAt__c
      LIMIT 1
    ];
    return waitingLogs.isEmpty() ? null : waitingLogs[0].NextAttemptAt__c;
  }

  /**
   * @description : 승인된 공급 제한 페널티를 물류 시스템에 통보한다. 2xx면 응답을 돌려주고, 그 밖에는 예외를 던진다.
   * @author      : 이은석(Kai) | 2026.10.14
   * @param penalty Id · PenaltyType__c · Status__c · StartDate__c · EndDate__c · Reason__c ·
   *                Franchise__r.StoreCode__c 가 조회된 페널티
   * @return HttpResponse 2xx 응답
   * @throws LogisticsNotifyException 입력 오류 · 4xx(재시도 불가) / 429 · 5xx · 시간 초과(재시도 대상)
   **/
  public static HttpResponse notifySupplyRestriction(Penalty__c penalty) {
    validate(penalty);

    HttpRequest req = new HttpRequest();
    req.setEndpoint(ENDPOINT);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    // DESC: X-Correlation-Id = 페널티 Id — 멱등성 키(물류 시스템과의 협의 항목). 시간 초과처럼 "갔는지 모르는" 실패 뒤에
    //       재시도해도 물류 시스템이 같은 키는 한 번만 처리하게 한다. 공급 제한이 두 번 걸리면 제한 기간이 겹치거나 늘어나
    //       가맹점 매출에 직접 피해가 간다
    req.setHeader(HEADER_CORRELATION_ID, penalty.Id);
    req.setTimeout(TIMEOUT_MS);
    req.setBody(buildPayload(penalty));

    HttpResponse res;
    try {
      res = new Http().send(req);
    } catch (CalloutException e) {
      // NOTE: 응답이 없는 실패. 시간 초과만 재시도 대상 — 상대가 처리했는지 모르는 상태라 멱등성 키에 기대어 다시 보낸다.
      //       주소 · 인증 · 권한 문제(호스트 없음, External Credential 접근 불가 등)는 다시 보내도 같아 사람이 확인한다
      // WARN: 시간 초과 판별을 메시지 문구로 한다. 플랫폼 문구가 바뀌면 재시도 대상이 빠질 수 있다 — 인터페이스 정의서에 기록
      Boolean isTimeout =
        e.getMessage() != null &&
        e.getMessage().containsIgnoreCase('timed out');
      throw failure(
        '물류 통보 연결 실패: ' + e.getMessage(),
        null,
        isTimeout,
        null
      );
    }

    Integer statusCode = res.getStatusCode();
    if (statusCode >= 200 && statusCode < 300) {
      return res;
    }
    // DESC: 429(호출 한도) · 5xx(상대 장애)는 시간이 지나면 풀릴 수 있어 재시도 대상.
    //       그 밖의 4xx(매장코드 미등록 · 요청 형식 · 인증)는 몇 번을 보내도 같으므로 재시도하지 않고 사람이 확인한다
    Boolean retryable =
      statusCode == HTTP_TOO_MANY_REQUESTS ||
      statusCode >= 500;
    throw failure(
      '물류 통보 실패 (HTTP ' + statusCode + ')',
      statusCode,
      retryable,
      res.getBody()
    );
  }

  // NOTE: 2xx인데 본문이 예상과 다르면 접수번호만 비운다 — 물류 시스템은 이미 접수했으므로 실패로 바꾸지 않는다
  private static String readRequestNo(String body) {
    try {
      Object requestNo = ((Map<String, Object>) JSON.deserializeUntyped(body))
        .get('requestNo');
      return requestNo == null ? null : String.valueOf(requestNo);
    } catch (Exception e) {
      return null;
    }
  }

  // DESC: 보내도 거절될 요청은 보내지 않는다. 데이터 문제라 재시도 불가
  private static void validate(Penalty__c penalty) {
    List<String> problems = new List<String>();
    if (penalty == null || penalty.Id == null) {
      throw failure('저장된 페널티만 통보할 수 있습니다.', null, false, null);
    }
    if (penalty.PenaltyType__c != PENALTY_TYPE_SUPPLY_RESTRICTION) {
      problems.add('유형이 공급 제한이 아님');
    }
    if (penalty.Status__c != PENALTY_STATUS_APPROVED) {
      problems.add('승인 전');
    }
    if (String.isBlank(penalty.Franchise__r?.StoreCode__c)) {
      problems.add('가맹점 매장코드 없음');
    }
    if (penalty.StartDate__c == null || penalty.EndDate__c == null) {
      problems.add('제한 기간 없음');
    }
    if (!problems.isEmpty()) {
      throw failure(
        '물류 통보 대상이 아닙니다: ' + String.join(problems, ', '),
        null,
        false,
        null
      );
    }
  }

  // DESC: 물류 시스템이 매장을 식별하는 키는 매장코드(Account.StoreCode__c, External Id)다. Salesforce Id는 보내지 않는다
  // NOTE: 로그에 요청 본문을 남길 때 검증 전에도 부르므로 가맹점이 비어 있어도 NPE가 나지 않게 ?.를 쓴다
  private static String buildPayload(Penalty__c penalty) {
    return JSON.serialize(
      new Map<String, Object>{
        'storeCode' => penalty.Franchise__r?.StoreCode__c,
        'startDate' => penalty.StartDate__c,
        'endDate' => penalty.EndDate__c,
        'reason' => penalty.Reason__c
      }
    );
  }

  private static String truncate(String value, Integer maxLength) {
    return value == null ? null : value.left(maxLength);
  }

  private static LogisticsNotifyException failure(
    String message,
    Integer statusCode,
    Boolean retryable,
    String responseBody
  ) {
    LogisticsNotifyException e = new LogisticsNotifyException(message);
    e.statusCode = statusCode;
    e.retryable = retryable;
    e.responseBody = responseBody;
    return e;
  }
}
