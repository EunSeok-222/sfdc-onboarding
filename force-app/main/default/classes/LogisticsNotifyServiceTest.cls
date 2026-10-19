/* ======================================================================================
 * @description : 물류 통보 콜아웃(BR-08 후단)의 요청 형식과 상태코드별 재시도 분기를 검증하는 테스트 클래스
 * @testTarget  : LogisticsNotifyService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 — 201 · 503 · 404 · 429 · 시간 초과 · 입력 검증
 *  2026.10.18   Kai        Updated     비활성 페널티 소유자 → 로그 기본 소유자 검증 추가(Step 7-A)
 *  2026.10.19   Kai        Updated     기간 없음 · 기간 역전은 콜아웃 없이 거절 — 검증 규칙 때문에 저장할 수 없어 인메모리 레코드로 검증
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

  // 증명: 기간 역전 · 기간 없음은 콜아웃 없이 거절된다(이중 방어) — 검증 규칙 PeriodStartBeforeEnd와 기간 자동 채움 때문에
  //       DB에는 이런 공급 제한을 저장할 수 없으므로 저장된 레코드를 메모리에서만 바꿔 넘긴다
  @IsTest
  static void notify_reversedOrMissingPeriod_isRejectedWithoutCallout() {
    Penalty__c reversed = getPenalty();
    reversed.StartDate__c = Date.today().addDays(2);
    reversed.EndDate__c = Date.today().addDays(1);
    Penalty__c missing = getPenalty();
    missing.EndDate__c = null;
    LogisticsNotifyMock mock = new LogisticsNotifyMock(201, null);
    Test.setMock(HttpCalloutMock.class, mock);

    List<String> messages = new List<String>();
    Test.startTest();
    for (Penalty__c penalty : new List<Penalty__c>{ reversed, missing }) {
      try {
        LogisticsNotifyService.notifySupplyRestriction(penalty);
      } catch (LogisticsNotifyService.LogisticsNotifyException e) {
        Assert.isFalse(e.retryable, '데이터 문제는 재시도해도 같다');
        messages.add(e.getMessage());
      }
    }
    Test.stopTest();

    Assert.areEqual(2, messages.size(), '두 건 모두 거절되어야 한다');
    Assert.isTrue(
      messages[0].contains('시작일이 종료일보다 늦음'),
      '기간 역전 이유가 있어야 한다. 실제: ' + messages[0]
    );
    Assert.isTrue(
      messages[1].contains('제한 기간 없음'),
      '기간 없음 이유가 있어야 한다. 실제: ' + messages[1]
    );
    Assert.isNull(mock.lastRequest, '거절할 요청은 보내지 않아야 한다');
  }

  // 증명: 페널티 소유자가 비활성이면(퇴사 등) 로그 읽기 권한이 있어도 로그 소유자로 지정하지 않는다 —
  //       지정하면 INACTIVE_OWNER_OR_USER로 승인 트랜잭션 전체가 실패한다
  @IsTest
  static void requestNotifications_inactiveOwner_keepsDefaultOwner() {
    User owner = TestDataFactory.createSvUser('통보테스트퇴사SV', true);
    // NOTE: 사용자 · 권한 집합(설정 개체) DML을 업무 데이터 DML과 분리해 Mixed DML을 피한다
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new PermissionSetAssignment(
        AssigneeId = owner.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'PenaltyLogisticsAccess'
        ]
        .Id
      );
    }
    Penalty__c penalty = getPenalty();
    penalty.OwnerId = owner.Id;
    update penalty;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      update new User(Id = owner.Id, IsActive = false);
    }

    // NOTE: Test.startTest/stopTest를 쓰지 않는다 — stopTest가 이벤트를 전달하면 Queueable 콜아웃까지 돈다.
    //       이 테스트는 승인 트랜잭션의 로그 기록(소유자 판정)만 본다
    LogisticsNotifyService.requestNotifications(
      new List<Penalty__c>{
        [SELECT Id, OwnerId FROM Penalty__c WHERE Id = :penalty.Id]
      }
    );

    IntegrationLog__c log = [SELECT OwnerId FROM IntegrationLog__c];
    Assert.areEqual(
      UserInfo.getUserId(),
      log.OwnerId,
      '비활성 소유자 대신 기본 소유자(insert한 사용자)'
    );
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
