/* ======================================================================================
 * @description : 물류 통보 이벤트 → Queueable의 로그 처리(성공 · 재시도대기 · 실패 · 중단 · 10건 초과)와
 *                실제 승인 시 승인자 컨텍스트에서 콜아웃하지 않는지를 검증하는 테스트 클래스
 * @testTarget  : LogisticsNotifyQueueable, LogisticsNotifyEventTriggerHandler, LogisticsNotifyService.processPendingLogs
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.16   Kai        Created     최초 작성 — 201 · 503 · 404 · 3회 초과 · 10건 초과, 실제 승인 후 권역팀장 runAs
 *  2026.10.17   Kai        Updated     로그 소유자 규칙 두 경우(SV 읽기 권한 유무) · 큐 밖 실행 시 다음 job · 지연 job 추가
 * ======================================================================================
 *  @see         : LogisticsNotifyMock.cls, Penalty__c.Penalty_Approval
 *  @note        : 처리는 이벤트 전달(Test.getEventBus().deliver()) → 이벤트 트리거 → Queueable(Test.stopTest()) 순서로 돈다.
 *                 Test.setMock은 Test.startTest() 앞에서 호출한다
 * ======================================================================================*/
@IsTest
private class LogisticsNotifyQueueableTest {
  private static final String STATUS_PENDING = '승인대기';
  private static final String REQUEST_NO = 'SR-000123';
  private static final String CREATED_BODY =
    '{"status":"RECEIVED","requestNo":"' +
    REQUEST_NO +
    '"}';

  // 증명: 201이면 로그가 성공 · 상태코드 · 접수번호 · 응답 본문으로 기록되고, 요청 본문에 인증 정보가 없다
  @IsTest
  static void deliverEvent_created_logSucceeds() {
    insertPendingLogs(1, LogisticsNotifyService.LOG_STATUS_PENDING, 0);
    Test.setMock(
      HttpCalloutMock.class,
      new LogisticsNotifyMock(201, CREATED_BODY)
    );

    deliverWakeUpEvent();

    IntegrationLog__c log = getOnlyLog();
    Assert.areEqual(
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      log.Status__c,
      '2xx면 성공'
    );
    Assert.areEqual(201, log.StatusCode__c, '상태코드 기록');
    Assert.areEqual(REQUEST_NO, log.RequestNo__c, '접수번호 기록');
    Assert.areEqual(1, log.AttemptCount__c, '시도 1회');
    Assert.isNull(log.NextAttemptAt__c, '성공이면 다음 시도 없음');
    Assert.isTrue(log.ResponseBody__c.contains(REQUEST_NO), '응답 본문 기록');
    Assert.isTrue(
      log.RequestBody__c.contains('storeCode'),
      '요청 본문(JSON) 기록'
    );
    Assert.isFalse(
      log.RequestBody__c.containsIgnoreCase('Authorization') ||
      log.ResponseBody__c.containsIgnoreCase('Bearer'),
      '인증 헤더 · 토큰은 로그에 남기지 않는다'
    );
    Assert.isNull(
      LogisticsNotifyQueueable.chainedDelayMinutesInTest,
      '남은 일이 없으면 다음 job을 넣지 않는다'
    );
  }

  // 증명: 503(재시도 대상) 첫 실패면 재시도대기 · 다음 시도 1분 뒤 · 1분 지연 job
  @IsTest
  static void deliverEvent_serviceUnavailable_waitsOneMinute() {
    insertPendingLogs(1, LogisticsNotifyService.LOG_STATUS_PENDING, 0);
    Test.setMock(
      HttpCalloutMock.class,
      new LogisticsNotifyMock(503, '{"error":"unavailable"}')
    );
    Datetime before = Datetime.now();

    deliverWakeUpEvent();

    IntegrationLog__c log = getOnlyLog();
    Assert.areEqual(
      LogisticsNotifyService.LOG_STATUS_RETRY,
      log.Status__c,
      '5xx는 재시도대기'
    );
    Assert.areEqual(1, log.AttemptCount__c, '시도 1회');
    Assert.areEqual(503, log.StatusCode__c, '상태코드 기록');
    Assert.isTrue(
      log.NextAttemptAt__c >= before.addSeconds(59) &&
        log.NextAttemptAt__c <= Datetime.now().addMinutes(1),
      '첫 재시도는 1분 뒤. 실제: ' + log.NextAttemptAt__c
    );
    Assert.areEqual(
      1,
      LogisticsNotifyQueueable.chainedDelayMinutesInTest,
      '1분 지연 job을 넣는다'
    );
  }

  // 증명: 404(재시도 불가)면 실패 — 다시 보내지 않는다
  @IsTest
  static void deliverEvent_notFound_isFailed() {
    insertPendingLogs(1, LogisticsNotifyService.LOG_STATUS_PENDING, 0);
    Test.setMock(
      HttpCalloutMock.class,
      new LogisticsNotifyMock(404, '{"error":"store not found"}')
    );

    deliverWakeUpEvent();

    IntegrationLog__c log = getOnlyLog();
    Assert.areEqual(
      LogisticsNotifyService.LOG_STATUS_FAILED,
      log.Status__c,
      '4xx(429 제외)는 실패'
    );
    Assert.areEqual(404, log.StatusCode__c, '상태코드 기록');
    Assert.isNotNull(log.ErrorMessage__c, '실패 사유 기록');
    Assert.isNull(log.NextAttemptAt__c, '다시 보내지 않는다');
    Assert.isNull(
      LogisticsNotifyQueueable.chainedDelayMinutesInTest,
      '재시도 job을 넣지 않는다'
    );
  }

  // 증명: 재시도 3회를 다 쓴 로그(시도 3회)가 또 재시도 대상으로 실패하면 중단(시도 4회)
  @IsTest
  static void deliverEvent_retryableAfterThreeRetries_isAborted() {
    insertPendingLogs(1, LogisticsNotifyService.LOG_STATUS_RETRY, 3);
    Test.setMock(
      HttpCalloutMock.class,
      new LogisticsNotifyMock(503, '{"error":"unavailable"}')
    );

    deliverWakeUpEvent();

    IntegrationLog__c log = getOnlyLog();
    Assert.areEqual(
      LogisticsNotifyService.LOG_STATUS_ABORTED,
      log.Status__c,
      '최초 1회 + 재시도 3회 뒤에도 실패하면 중단'
    );
    Assert.areEqual(4, log.AttemptCount__c, '시도 4회');
    Assert.isNull(log.NextAttemptAt__c, '중단이면 다음 시도 없음');
  }

  // 증명: 처리 대기가 10건을 넘으면 이번 실행은 10건만 보내고 즉시 다음 job으로 넘긴다
  @IsTest
  static void deliverEvent_moreThanBatchSize_chainsImmediately() {
    insertPendingLogs(
      LogisticsNotifyService.BATCH_SIZE + 2,
      LogisticsNotifyService.LOG_STATUS_PENDING,
      0
    );
    Test.setMock(
      HttpCalloutMock.class,
      new LogisticsNotifyMock(201, CREATED_BODY)
    );

    deliverWakeUpEvent();

    Assert.areEqual(
      LogisticsNotifyService.BATCH_SIZE,
      countLogs(LogisticsNotifyService.LOG_STATUS_SUCCESS),
      '한 실행은 10건까지만(콜아웃 누적 120초 ÷ 타임아웃 10초)'
    );
    Assert.areEqual(
      2,
      countLogs(LogisticsNotifyService.LOG_STATUS_PENDING),
      '나머지 2건은 전송대기로 남는다'
    );
    Assert.areEqual(
      0,
      LogisticsNotifyQueueable.chainedDelayMinutesInTest,
      '남은 건은 즉시 다음 job'
    );
  }

  // 증명: Queueable 밖에서 실행되면(이벤트 트리거가 넣은 첫 job과 같은 조건) 10건 초과 시 실제로 다음 job을 넣고,
  //       그 job이 나머지를 보낸다
  @IsTest
  static void executeOutsideQueue_moreThanBatchSize_enqueuesNextJob() {
    insertPendingLogs(
      LogisticsNotifyService.BATCH_SIZE + 2,
      LogisticsNotifyService.LOG_STATUS_PENDING,
      0
    );
    Test.setMock(
      HttpCalloutMock.class,
      new LogisticsNotifyMock(201, CREATED_BODY)
    );

    Test.startTest();
    new LogisticsNotifyQueueable().execute(null);
    Integer enqueuedJobs = Limits.getQueueableJobs();
    Test.stopTest();

    Assert.areEqual(1, enqueuedJobs, '남은 건이 있으면 다음 job 1개');
    Assert.areEqual(
      LogisticsNotifyService.BATCH_SIZE + 2,
      countLogs(LogisticsNotifyService.LOG_STATUS_SUCCESS),
      '다음 job이 나머지 2건을 보낸다'
    );
  }

  // 증명: 재시도 대상 실패면 지연 job을 넣고, 그 job은 다음 시도 시각 전에는 다시 보내지 않는다
  @IsTest
  static void executeOutsideQueue_retryable_enqueuesDelayedJob() {
    insertPendingLogs(1, LogisticsNotifyService.LOG_STATUS_PENDING, 0);
    Test.setMock(
      HttpCalloutMock.class,
      new LogisticsNotifyMock(503, '{"error":"unavailable"}')
    );

    Test.startTest();
    new LogisticsNotifyQueueable().execute(null);
    Integer enqueuedJobs = Limits.getQueueableJobs();
    Test.stopTest();

    Assert.areEqual(1, enqueuedJobs, '재시도를 위한 지연 job 1개');
    IntegrationLog__c log = getOnlyLog();
    Assert.areEqual(
      LogisticsNotifyService.LOG_STATUS_RETRY,
      log.Status__c,
      '재시도대기 유지'
    );
    Assert.areEqual(
      1,
      log.AttemptCount__c,
      '다음 시도 시각 전에는 다시 보내지 않는다(시도 1회 그대로)'
    );
  }

  // 증명: 실제 승인(제출 → 권역팀장 승인)은 「물류 연동」 없이도 성공하고, 승인자 컨텍스트에서는 콜아웃 없이
  //       로그 「전송대기」 1건만 남는다. 승인된 페널티 값은 바뀌지 않고, 로그 소유자는 페널티 소유자(SV)다
  @IsTest
  static void approvedByRegionManager_svCanReadLogs_logOwnedBySv() {
    ApprovalOutcome outcome = approveAsRegionManager(true);

    assertApprovedWithoutCallout(outcome);
    Assert.areEqual(
      outcome.sv.Id,
      getOnlyLog().OwnerId,
      '로그 읽기 권한이 있는 페널티 소유자(SV)가 로그 소유자'
    );
  }

  // 증명: 페널티 소유자에게 로그 읽기 권한이 없어도 승인은 막히지 않고, 로그는 기본 소유자(승인자)로 남는다
  @IsTest
  static void approvedByRegionManager_svCannotReadLogs_approvalNotBlocked() {
    ApprovalOutcome outcome = approveAsRegionManager(false);

    assertApprovedWithoutCallout(outcome);
    Assert.areEqual(
      outcome.regionManager.Id,
      getOnlyLog().OwnerId,
      '소유자로 넘길 수 없으면(TRANSFER_REQUIRES_READ) insert한 사용자(승인자)가 소유자'
    );
  }

  // ---------------------------------------------------------------- 승인 시나리오 도우미

  private class ApprovalOutcome {
    User sv;
    User regionManager;
    Id penaltyId;
    Penalty__c before;
    Penalty__c after;
    Integer calloutsInApproval;
  }

  // DESC: SV 소유 공급 제한 페널티를 SV가 제출하고, SV의 Manager(권역팀장)가 승인한다 — Approval Process 「페널티 승인」 그대로
  // NOTE: Test.startTest/stopTest를 쓰지 않는다 — 쓰면 커밋 후 발행 이벤트가 전달돼 연동 처리까지 돌기 때문.
  //       이 시나리오는 승인자 컨텍스트만 본다
  private static ApprovalOutcome approveAsRegionManager(Boolean svCanReadLogs) {
    ApprovalOutcome outcome = new ApprovalOutcome();
    User regionManager = TestDataFactory.createRegionManagerUser(
      '승인테스트팀장',
      false
    );
    User sv = TestDataFactory.createSvUser('승인테스트SV', false);
    // NOTE: 실제 org와 같은 역할 계층(권역팀장 - 수도권 > SV - 수도권)을 준다. 역할이 없으면 승인자가 SV 소유
    //       페널티 · 가맹점을 볼 경로가 없어 승인 단계에서 INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY가 난다
    Map<String, Id> roleIdsByDeveloperName = new Map<String, Id>();
    for (UserRole role : [
      SELECT Id, DeveloperName
      FROM UserRole
      WHERE DeveloperName IN ('RegionManagerCapital', 'SupervisorCapital')
    ]) {
      roleIdsByDeveloperName.put(role.DeveloperName, role.Id);
    }
    regionManager.UserRoleId = roleIdsByDeveloperName.get(
      'RegionManagerCapital'
    );
    sv.UserRoleId = roleIdsByDeveloperName.get('SupervisorCapital');
    // DESC: 역할이 있는 사용자 insert는 설정(setup) DML — runAs로 업무 데이터 DML과 트랜잭션을 나눠 Mixed DML을 피한다
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert regionManager;
      sv.ManagerId = regionManager.Id;
      insert sv;
      if (svCanReadLogs) {
        // DESC: 실제 org처럼 SV에게 「인터페이스 로그 조회」를 준다 — 권한 집합 할당도 설정 DML이라 이 블록 안에서
        insert new PermissionSetAssignment(
          AssigneeId = sv.Id,
          PermissionSetId = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'PenaltyLogisticsAccess'
          ]
          .Id
        );
      }
    }
    // NOTE: 담당 매장은 SV 소유 — 관리자 소유 가맹점이면 SV가 제출할 때 참조 레코드 접근 권한이 없어 막힌다
    List<Account> franchises = TestDataFactory.createFranchises(1, false);
    franchises[0].OwnerId = sv.Id;
    insert franchises;
    Penalty__c penalty = TestDataFactory.createSupplyRestrictionPenalties(
      franchises,
      false
    )[0];
    penalty.Status__c = STATUS_PENDING;
    penalty.OwnerId = sv.Id;
    insert penalty;
    // DESC: 소유자(SV)가 제출 → 승인자는 소유자의 Manager(권역팀장) — Approval Process 「페널티 승인」 그대로
    System.runAs(sv) {
      Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
      submit.setObjectId(penalty.Id);
      Approval.process(submit);
    }
    outcome.before = getPenalty(penalty.Id);

    Integer calloutsInApproval;
    System.runAs(regionManager) {
      ProcessInstanceWorkitem workItem = [
        SELECT Id
        FROM ProcessInstanceWorkitem
        WHERE ProcessInstance.TargetObjectId = :penalty.Id
        WITH SYSTEM_MODE
      ];
      Approval.ProcessWorkitemRequest approve = new Approval.ProcessWorkitemRequest();
      approve.setWorkitemId(workItem.Id);
      approve.setAction('Approve');
      Approval.ProcessResult result = Approval.process(approve);
      Assert.isTrue(result.isSuccess(), '「물류 연동」이 없어도 승인돼야 한다');
      calloutsInApproval = Limits.getCallouts();
    }

    outcome.sv = sv;
    outcome.regionManager = regionManager;
    outcome.penaltyId = penalty.Id;
    outcome.after = getPenalty(penalty.Id);
    outcome.calloutsInApproval = calloutsInApproval;
    return outcome;
  }

  // DESC: 두 승인 시나리오의 공통 검증 — 콜아웃 0건 · 승인 상태 · 페널티 값 그대로 · 로그 전송대기 1건 · 상관 ID
  private static void assertApprovedWithoutCallout(ApprovalOutcome outcome) {
    Assert.areEqual(
      0,
      outcome.calloutsInApproval,
      '승인자 컨텍스트에서는 콜아웃하지 않는다'
    );
    Assert.areEqual(
      LogisticsNotifyService.PENALTY_STATUS_APPROVED,
      outcome.after.Status__c,
      '최종 승인 Field Update로 승인 상태'
    );
    Assert.areEqual(
      outcome.before.Reason__c,
      outcome.after.Reason__c,
      '사유 그대로'
    );
    Assert.areEqual(
      outcome.before.StartDate__c,
      outcome.after.StartDate__c,
      '시작일 그대로'
    );
    Assert.areEqual(
      outcome.before.EndDate__c,
      outcome.after.EndDate__c,
      '종료일 그대로'
    );
    Assert.areEqual(
      outcome.before.OwnerId,
      outcome.after.OwnerId,
      '소유자 그대로'
    );
    IntegrationLog__c log = getOnlyLog();
    Assert.areEqual(
      LogisticsNotifyService.LOG_STATUS_PENDING,
      log.Status__c,
      '승인 직후 로그는 전송대기 1건'
    );
    Assert.areEqual(
      String.valueOf(outcome.penaltyId),
      log.CorrelationId__c,
      '상관 ID = 페널티 Id'
    );
  }

  // ---------------------------------------------------------------- 도우미

  // DESC: 승인된 공급 제한 페널티와 그 로그를 만든다
  private static void insertPendingLogs(
    Integer count,
    String status,
    Integer attemptCount
  ) {
    List<Penalty__c> penalties = TestDataFactory.createSupplyRestrictionPenalties(
      TestDataFactory.createFranchises(count, true),
      true
    );
    TestDataFactory.createLogisticsNotifyLogs(
      penalties,
      status,
      attemptCount,
      true
    );
  }

  // DESC: 깨우기 이벤트를 발행 · 전달하고, 이벤트 트리거가 넣은 Queueable을 stopTest에서 실행한다
  private static void deliverWakeUpEvent() {
    Test.startTest();
    EventBus.publish(
      new LogisticsNotifyEvent__e(
        InterfaceId__c = LogisticsNotifyService.INTERFACE_ID
      )
    );
    Test.getEventBus().deliver();
    Test.stopTest();
  }

  private static IntegrationLog__c getOnlyLog() {
    List<IntegrationLog__c> logs = [
      SELECT
        Status__c,
        StatusCode__c,
        RequestNo__c,
        AttemptCount__c,
        NextAttemptAt__c,
        RequestBody__c,
        ResponseBody__c,
        ErrorMessage__c,
        CorrelationId__c,
        OwnerId
      FROM IntegrationLog__c
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(1, logs.size(), '로그는 1건이어야 한다');
    return logs[0];
  }

  private static Integer countLogs(String status) {
    return [
      SELECT COUNT()
      FROM IntegrationLog__c
      WHERE Status__c = :status
      WITH SYSTEM_MODE
    ];
  }

  private static Penalty__c getPenalty(Id penaltyId) {
    return [
      SELECT Status__c, Reason__c, StartDate__c, EndDate__c, OwnerId
      FROM Penalty__c
      WHERE Id = :penaltyId
      WITH SYSTEM_MODE
    ];
  }
}
