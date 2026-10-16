/* ======================================================================================
 * @description : 물류 통보 콜아웃(BR-08 후단)의 요청 형식과 상태코드별 재시도 분기를 검증하는 테스트 클래스
 * @testTarget  : LogisticsNotifyService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 — 201 · 503 · 404 · 429 · 시간 초과 · 입력 검증
 * ======================================================================================
 *  @see         : LogisticsNotifyMock.cls
 *  @note        : Test.setMock은 Test.startTest() 앞에서 호출한다
 * ======================================================================================*/
@IsTest
private class LogisticsNotifyServiceTest {
  @TestSetup
  static void setupData() {
    TestDataFactory.createSupplyRestrictionPenalties(
      TestDataFactory.createFranchises(1, true),
      true
    );
  }

  // 증명: 201이면 응답을 그대로 돌려주고, 요청에 매장코드 · 기간 · 사유와 멱등성 키(페널티 Id)가 실린다
  @IsTest
  static void notify_created_returnsResponseWithPayload() {
    Penalty__c penalty = getPenalty();
    LogisticsNotifyMock mock = new LogisticsNotifyMock(
      201,
      '{"result":"accepted"}'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    HttpResponse res = LogisticsNotifyService.notifySupplyRestriction(penalty);
    Test.stopTest();

    Assert.areEqual(
      201,
      res.getStatusCode(),
      '2xx는 응답을 그대로 돌려줘야 한다'
    );
    Assert.areEqual(
      String.valueOf(penalty.Id),
      mock.lastRequest.getHeader(LogisticsNotifyService.HEADER_CORRELATION_ID),
      '멱등성 키는 페널티 Id여야 같은 페널티의 재시도를 물류 시스템이 알아본다'
    );
    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      mock.lastRequest.getBody()
    );
    Assert.areEqual(
      penalty.Franchise__r.StoreCode__c,
      payload.get('storeCode'),
      '물류 시스템은 매장을 매장코드로 식별한다'
    );
    Assert.areEqual(
      String.valueOf(penalty.StartDate__c),
      payload.get('startDate'),
      '제한 시작일이 실려야 한다'
    );
    Assert.areEqual(
      String.valueOf(penalty.EndDate__c),
      payload.get('endDate'),
      '제한 종료일이 실려야 한다'
    );
    Assert.areEqual(
      penalty.Reason__c,
      payload.get('reason'),
      '사유가 실려야 한다'
    );
  }

  // 증명: 503(상대 장애)은 시간이 지나면 풀릴 수 있어 재시도 대상으로 분류된다
  @IsTest
  static void notify_serverError_isRetryable() {
    LogisticsNotifyService.LogisticsNotifyException e = notifyExpectingFailure(
      new LogisticsNotifyMock(503, '{"error":"unavailable"}')
    );

    Assert.areEqual(503, e.statusCode, '상태코드를 호출자에게 넘겨야 한다');
    Assert.isTrue(e.retryable, '5xx는 재시도 대상이어야 한다');
    Assert.areEqual(
      '{"error":"unavailable"}',
      e.responseBody,
      '원인 확인용으로 응답 본문을 넘겨야 한다'
    );
  }

  // 증명: 404(매장코드 미등록 등)는 몇 번을 보내도 같아 재시도하지 않는다 — 사람이 확인할 대상
  @IsTest
  static void notify_notFound_isNotRetryable() {
    LogisticsNotifyService.LogisticsNotifyException e = notifyExpectingFailure(
      new LogisticsNotifyMock(404, '{"error":"store not found"}')
    );

    Assert.areEqual(404, e.statusCode, '상태코드를 호출자에게 넘겨야 한다');
    Assert.isFalse(e.retryable, '4xx는 재시도하지 않아야 한다');
  }

  // 증명: 429(호출 한도 초과)는 4xx지만 간격을 두면 풀리므로 재시도 대상이다
  @IsTest
  static void notify_tooManyRequests_isRetryable() {
    LogisticsNotifyService.LogisticsNotifyException e = notifyExpectingFailure(
      new LogisticsNotifyMock(429, null)
    );

    Assert.areEqual(429, e.statusCode, '상태코드를 호출자에게 넘겨야 한다');
    Assert.isTrue(e.retryable, '429는 4xx 중 유일한 재시도 대상이어야 한다');
  }

  // 증명: 시간 초과는 응답이 없어 상대가 처리했는지 모른다 → 상태코드 없이 재시도 대상(멱등성 키에 기댄다)
  @IsTest
  static void notify_timeout_isRetryable() {
    LogisticsNotifyService.LogisticsNotifyException e = notifyExpectingFailure(
      LogisticsNotifyMock.timingOut()
    );

    Assert.isNull(e.statusCode, '응답이 없으면 상태코드는 null이어야 한다');
    Assert.isTrue(e.retryable, '시간 초과는 재시도 대상이어야 한다');
  }

  // 증명: 통보 대상이 아닌 페널티(승인 전 · 매장코드 없음)는 콜아웃 없이 바로 거절된다 — 재시도 불가
  @IsTest
  static void notify_invalidPenalty_isRejectedWithoutCallout() {
    Penalty__c penalty = getPenalty();
    penalty.Status__c = '승인대기';
    penalty.Franchise__r.StoreCode__c = null;
    LogisticsNotifyMock mock = new LogisticsNotifyMock(201, null);
    Test.setMock(HttpCalloutMock.class, mock);

    LogisticsNotifyService.LogisticsNotifyException caught;
    Test.startTest();
    try {
      LogisticsNotifyService.notifySupplyRestriction(penalty);
    } catch (LogisticsNotifyService.LogisticsNotifyException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(caught, '통보 대상이 아니면 예외가 나야 한다');
    Assert.isFalse(caught.retryable, '데이터 문제는 재시도해도 같다');
    Assert.isTrue(
      caught.getMessage().contains('승인 전') &&
      caught.getMessage().contains('매장코드 없음'),
      '거절 이유를 모두 알려줘야 한다. 실제: ' + caught.getMessage()
    );
    Assert.isNull(mock.lastRequest, '거절할 요청은 보내지 않아야 한다');
  }

  // NOTE: Assert.fail을 try 안에 두면 catch가 그 실패까지 삼킨다 → 결과를 변수로 받고 밖에서 검증한다
  private static LogisticsNotifyService.LogisticsNotifyException notifyExpectingFailure(
    LogisticsNotifyMock mock
  ) {
    Penalty__c penalty = getPenalty();
    Test.setMock(HttpCalloutMock.class, mock);

    LogisticsNotifyService.LogisticsNotifyException caught;
    Test.startTest();
    try {
      LogisticsNotifyService.notifySupplyRestriction(penalty);
    } catch (LogisticsNotifyService.LogisticsNotifyException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      '2xx가 아니면 LogisticsNotifyException이 나야 한다'
    );
    Assert.isNotNull(mock.lastRequest, '요청은 실제로 나가야 한다');
    return caught;
  }

  private static Penalty__c getPenalty() {
    return [
      SELECT
        Id,
        PenaltyType__c,
        Status__c,
        StartDate__c,
        EndDate__c,
        Reason__c,
        Franchise__r.StoreCode__c
      FROM Penalty__c
      LIMIT 1
    ];
  }
}
