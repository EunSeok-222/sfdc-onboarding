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
 *  2026.10.17   Kai        Updated     승인 시나리오 재구성 — 권한 있음(이벤트 전달 → 전송 성공) / 없음(발행 실패 기록) (Step 6 E2E 수정)
 *  2026.10.17   Kai        Updated     연동 사용자(소유자 아님 · 역할 없음) runAs로 다른 사람 소유 로그 처리 검증 추가
 *  2026.10.19   Kai        Updated     실패 · 중단이면 「연동 알림 수신자」 그룹 알림(대상 = 페널티), 성공이면 알림 없음
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
    Assert.areEqual(
      0,
      OperationAlertService.attemptedAlerts.size(),
      '성공이면 연동 실패 알림을 보내지 않는다'
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
    assertIntegrationAlert(LogisticsNotifyService.LOG_STATUS_FAILED);
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
    assertIntegrationAlert(LogisticsNotifyService.LOG_STATUS_ABORTED);
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

  // 증명: 실행 사용자(연동 사용자 프로필, 역할 없음)가 로그 · 페널티의 소유자가 아니어도 대기 로그를 찾아 보낸다
  //       — 아웃박스 처리는 레코드 공유와 무관해야 한다(D11 Step 6: with sharing이라 연동 사용자 조회가 0건)
  @IsTest
  static void processAsIntegrationUser_logsOwnedByOthers_areSent() {
    User integrationUser = TestDataFactory.createIntegrationUser(
      '아웃박스테스트연동',
      true
    );
    // DESC: 로그 · 페널티 · 가맹점은 실행 중인 테스트 사용자 소유 — 연동 사용자에게는 공유 경로가 없다
    insertPendingLogs(1, LogisticsNotifyService.LOG_STATUS_PENDING, 0);
    Test.setMock(
      HttpCalloutMock.class,
      new LogisticsNotifyMock(201, CREATED_BODY)
    );

    Test.startTest();
    System.runAs(integrationUser) {
      new LogisticsNotifyQueueable().execute(null);
    }
    Test.stopTest();

    IntegrationLog__c log = getOnlyLog();
    Assert.areEqual(
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      log.Status__c,
      '소유자가 아니어도 연동 사용자가 대기 로그를 보내야 한다(0건 조회면 전송대기로 남는다)'
    );
    Assert.areEqual(REQUEST_NO, log.RequestNo__c, '접수번호 기록');
    Assert.areEqual(1, log.AttemptCount__c, '시도 1회');
  }

  // 증명: 권역팀장(「물류 통보 요청」 있음)이 승인하면 승인 컨텍스트에서는 콜아웃 없이 로그만 남고, 이벤트가 전달되면
  //       Queueable이 그 로그를 보낸다(성공 · 접수번호). 로그 소유자는 페널티 소유자(SV) — Step 6 E2E 자동 경로 그대로
  @IsTest
  static void approvedByRegionManager_withPermissions_eventDeliveredAndLogSent() {
    ApprovalOutcome outcome = prepareApproval(true, true);
    Test.setMock(
      HttpCalloutMock.class,
      new LogisticsNotifyMock(201, CREATED_BODY)
    );

    Test.startTest();
    approve(outcome);
    Test.getEventBus().deliver();
    Test.stopTest();

    assertApprovedWithoutCallout(outcome);
    IntegrationLog__c log = getOnlyLog();
    Assert.isNull(
      log.ErrorMessage__c,
      '발행 권한이 있으면 발행 실패 기록이 없다'
    );
    Assert.areEqual(
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      log.Status__c,
      '이벤트 전달 → Queueable이 로그를 보낸다'
    );
    Assert.areEqual(REQUEST_NO, log.RequestNo__c, '접수번호 기록');
    Assert.areEqual(
      outcome.sv.Id,
      log.OwnerId,
      '로그 읽기 권한이 있는 페널티 소유자(SV)가 로그 소유자'
    );
  }

  // 증명: 권역팀장에게 이벤트 발행 권한이 없으면 발행은 SaveResult로만 실패한다 — 승인은 막히지 않고, 로그는
  //       전송대기로 남아 오류 메시지에 발행 실패가 기록된다. 페널티 소유자가 로그를 못 읽으면 소유자는 승인자
  @IsTest
  static void approvedByRegionManager_withoutPermissions_recordsPublishFailure() {
    ApprovalOutcome outcome = prepareApproval(false, false);

    approve(outcome);

    assertApprovedWithoutCallout(outcome);
    IntegrationLog__c log = getOnlyLog();
    Assert.areEqual(
      LogisticsNotifyService.LOG_STATUS_PENDING,
      log.Status__c,
      '발행이 실패해도 로그는 전송대기로 남아 재처리할 수 있다'
    );
    Assert.isTrue(
      log.ErrorMessage__c != null &&
        log.ErrorMessage__c.startsWith('이벤트 발행 실패') &&
        log.ErrorMessage__c.contains('LogisticsNotifyEvent__e'),
      '발행 실패 사유를 로그에 남긴다. 실제: ' + log.ErrorMessage__c
    );
    Assert.areEqual(
      outcome.regionManager.Id,
      log.OwnerId,
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

  // DESC: SV 소유 공급 제한 페널티를 SV가 제출해 둔다(승인 대기). 승인은 approve()가 SV의 Manager(권역팀장)로 한다
  //       — Approval Process 「페널티 승인」 그대로
  // NOTE: 이벤트를 전달할 테스트만 approve()를 Test.startTest/stopTest로 감싼다. 감싸지 않으면 커밋 후 발행 이벤트가
  //       전달되지 않아 승인자 컨텍스트만 본다
  private static ApprovalOutcome prepareApproval(
    Boolean svCanReadLogs,
    Boolean regionManagerCanPublish
  ) {
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
      // DESC: 실제 org처럼 SV에게 「인터페이스 로그 조회」, 권역팀장에게 「물류 통보 요청」을 준다
      //       — 권한 집합 할당도 설정 DML이라 이 블록 안에서
      List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
      if (svCanReadLogs) {
        assignments.add(assignmentOf(sv.Id, 'PenaltyLogisticsAccess'));
      }
      if (regionManagerCanPublish) {
        assignments.add(
          assignmentOf(regionManager.Id, 'LogisticsNotifyRequestAccess')
        );
      }
      insert assignments;
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
    outcome.sv = sv;
    outcome.regionManager = regionManager;
    outcome.penaltyId = penalty.Id;
    outcome.before = getPenalty(penalty.Id);
    return outcome;
  }

  // DESC: 권역팀장으로 승인한다. 승인자에게는 「물류 연동」이 없다 — 승인자는 외부 호출을 하지 않는다
  private static void approve(ApprovalOutcome outcome) {
    System.runAs(outcome.regionManager) {
      ProcessInstanceWorkitem workItem = [
        SELECT Id
        FROM ProcessInstanceWorkitem
        WHERE ProcessInstance.TargetObjectId = :outcome.penaltyId
        WITH SYSTEM_MODE
      ];
      Approval.ProcessWorkitemRequest request = new Approval.ProcessWorkitemRequest();
      request.setWorkitemId(workItem.Id);
      request.setAction('Approve');
      Approval.ProcessResult result = Approval.process(request);
      Assert.isTrue(result.isSuccess(), '「물류 연동」이 없어도 승인돼야 한다');
      outcome.calloutsInApproval = Limits.getCallouts();
    }
    outcome.after = getPenalty(outcome.penaltyId);
  }

  private static PermissionSetAssignment assignmentOf(
    Id userId,
    String permissionSetName
  ) {
    return new PermissionSetAssignment(
      AssigneeId = userId,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = :permissionSetName
      ]
      .Id
    );
  }

  // DESC: 두 승인 시나리오의 공통 검증 — 승인 컨텍스트 콜아웃 0건 · 승인 상태 · 페널티 값 그대로 · 로그 1건 · 상관 ID
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
    Assert.areEqual(
      String.valueOf(outcome.penaltyId),
      getOnlyLog().CorrelationId__c,
      '승인된 페널티마다 로그 1건, 상관 ID = 페널티 Id'
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

  // DESC: 실패 · 중단 로그 1건 → 「연동 알림 수신자」 그룹에 알림 1건(대상 = 페널티, 제목에 상태)
  private static void assertIntegrationAlert(String status) {
    Assert.areEqual(
      1,
      OperationAlertService.attemptedAlerts.size(),
      status + ' 1건 → 알림 1건'
    );
    OperationAlertService.Alert alert = OperationAlertService.attemptedAlerts[0];
    Assert.areEqual(
      [SELECT Penalty__c FROM IntegrationLog__c WITH SYSTEM_MODE LIMIT 1]
      .Penalty__c,
      alert.targetId,
      '대상 = 페널티'
    );
    Assert.isTrue(
      alert.recipientIds.contains(
        OperationAlertService.getIntegrationAlertGroupId()
      ),
      '수신자 = 연동 알림 수신자 그룹'
    );
    Assert.isTrue(alert.title.contains(status), '제목에 상태: ' + alert.title);
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
