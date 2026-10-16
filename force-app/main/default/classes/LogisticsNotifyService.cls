/* ======================================================================================
 * @description : 공급 제한 페널티 승인 시 물류 시스템에 출고 제한을 통보하는 Outbound 콜아웃 (BR-08 후단) — 스텁
 * @testClass   : LogisticsNotifyServiceTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 — 통보 요청 · 상태코드별 재시도 분기 (호출부 연결 없는 스텁)
 * ======================================================================================
 *  @see         : LogisticsNotifyMock.cls, 요건 정의서 V1.0 BR-08 · As-Is 「승인·통보 지연」
 *  @note        : 트리거 · 승인 프로세스에 직접 연결하지 않는다. 승인 저장은 DML 트랜잭션 한가운데라 동기 콜아웃이
 *                 불가하다("You have uncommitted work pending"). 연결할 때는 Queueable(Database.AllowsCallouts)로
 *                 트랜잭션을 분리하고, 재시도는 LogisticsNotifyException.retryable을 보고 정한다
 * ======================================================================================*/
public with sharing class LogisticsNotifyService {
  public static final String ENDPOINT = 'callout:HankkiLogistics/v1/supply-restrictions';
  public static final String HEADER_CORRELATION_ID = 'X-Correlation-Id';
  public static final String PENALTY_TYPE_SUPPLY_RESTRICTION = '공급 제한';
  public static final String PENALTY_STATUS_APPROVED = '승인';

  // NOTE: 플랫폼 기본값도 10초지만 명시한다 — 기본값에 기대면 물류 시스템과 협의한 응답 한도가 코드에 드러나지 않고,
  //       기본값이 바뀌면 동작이 조용히 달라진다. 콜아웃 1건 최대 120초
  private static final Integer TIMEOUT_MS = 10000;
  private static final Integer HTTP_TOO_MANY_REQUESTS = 429;

  /**
   * @description : 물류 통보 실패. 호출자(향후 Queueable)가 재시도 여부를 판단할 수 있게 상태코드와 재시도 가능 여부를 담는다.
   **/
  public class LogisticsNotifyException extends Exception {
    // NOTE: 응답 자체가 없으면(연결 실패 · 시간 초과 · 입력 검증 실패) null
    public Integer statusCode;
    public Boolean retryable;
    public String responseBody;
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
  private static String buildPayload(Penalty__c penalty) {
    return JSON.serialize(
      new Map<String, Object>{
        'storeCode' => penalty.Franchise__r.StoreCode__c,
        'startDate' => penalty.StartDate__c,
        'endDate' => penalty.EndDate__c,
        'reason' => penalty.Reason__c
      }
    );
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
