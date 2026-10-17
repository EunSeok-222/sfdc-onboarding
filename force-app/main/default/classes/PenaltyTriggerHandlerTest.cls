/* ======================================================================================
 * @description : 페널티 트리거가 공급 제한 승인 전이에서만 물류 통보 요청(로그 · 이벤트)을 남기는지 검증하는 테스트 클래스
 * @testTarget  : PenaltyTriggerHandler, LogisticsNotifyService.requestNotifications
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.16   Kai        Created     최초 작성 — 200건 승인 → 로그 200건 · 이벤트, 경고 유형 0건, 이미 승인 재저장 0건
 * ======================================================================================
 *  @see         : Penalty.trigger, LogisticsNotifyEvent.trigger
 *  @note        : 이벤트를 전달하면 Queueable이 실제로 돌아 콜아웃하므로 그 테스트에서는 Mock을 건다
 * ======================================================================================*/
@IsTest
private class PenaltyTriggerHandlerTest {
  private static final Integer BULK_SIZE = 200;
  private static final String STATUS_PENDING = '승인대기';
  private static final String TYPE_WARNING = '경고';
  private static final String CREATED_BODY = '{"status":"RECEIVED","requestNo":"SR-000123"}';

  // 증명: 공급 제한 200건이 한 번에 승인되면 로그 200건(소유자 = 페널티 소유자)이 남고, 이벤트가 전달돼 처리가 시작된다
  @IsTest
  static void approveSupplyRestriction_bulk_createsLogsAndPublishesEvent() {
    List<Penalty__c> penalties = insertPenalties(
      LogisticsNotifyService.PENALTY_TYPE_SUPPLY_RESTRICTION,
      STATUS_PENDING
    );
    Test.setMock(
      HttpCalloutMock.class,
      new LogisticsNotifyMock(201, CREATED_BODY)
    );

    Test.startTest();
    approveAll(penalties);
    Integer calloutsInApproval = Limits.getCallouts();
    Integer jobsInApproval = Limits.getQueueableJobs();
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(
      0,
      calloutsInApproval,
      '승인 트랜잭션에서는 콜아웃하지 않는다'
    );
    Assert.areEqual(
      0,
      jobsInApproval,
      '승인 트랜잭션에서는 job을 넣지 않는다(이벤트 트리거가 넣는다)'
    );
    List<IntegrationLog__c> logs = [
      SELECT Status__c, OwnerId, Penalty__r.OwnerId
      FROM IntegrationLog__c
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(BULK_SIZE, logs.size(), '승인된 공급 제한마다 로그 1건');
    Assert.areEqual(
      logs[0].Penalty__r.OwnerId,
      logs[0].OwnerId,
      '로그 소유자는 페널티 소유자여야 한다(OWD 비공개 가시성)'
    );
    Assert.areEqual(
      LogisticsNotifyService.BATCH_SIZE,
      countLogs(LogisticsNotifyService.LOG_STATUS_SUCCESS),
      '이벤트가 전달되면 Queueable이 첫 10건을 보낸다 — 이벤트가 발행됐다는 증거'
    );
    Assert.areEqual(
      0,
      LogisticsNotifyQueueable.chainedDelayMinutesInTest,
      '남은 190건은 즉시 다음 job으로 넘긴다'
    );
  }

  // 증명: 경고 유형은 승인돼도 물류 통보 대상이 아니다
  @IsTest
  static void approveWarning_createsNoLog() {
    List<Penalty__c> penalties = insertPenalties(TYPE_WARNING, STATUS_PENDING);

    Test.startTest();
    approveAll(penalties);
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM IntegrationLog__c WITH SYSTEM_MODE],
      '경고 유형은 로그를 남기지 않는다'
    );
  }

  // 증명: 이미 승인인 공급 제한을 다시 저장해도(사유 수정 등) 다시 요청하지 않는다
  @IsTest
  static void resaveApprovedSupplyRestriction_createsNoLog() {
    List<Penalty__c> penalties = insertPenalties(
      LogisticsNotifyService.PENALTY_TYPE_SUPPLY_RESTRICTION,
      LogisticsNotifyService.PENALTY_STATUS_APPROVED
    );

    Test.startTest();
    for (Penalty__c penalty : penalties) {
      penalty.Reason__c = '사유 보완';
    }
    update penalties;
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM IntegrationLog__c WITH SYSTEM_MODE],
      '상태가 바뀌지 않은 재저장은 로그를 남기지 않는다'
    );
  }

  // ---------------------------------------------------------------- 도우미

  // DESC: 가맹점마다 1건씩, 유형 · 상태를 바꿔 DML 1번으로 넣는다
  private static List<Penalty__c> insertPenalties(String type, String status) {
    List<Penalty__c> penalties = TestDataFactory.createSupplyRestrictionPenalties(
      TestDataFactory.createFranchises(BULK_SIZE, true),
      false
    );
    for (Penalty__c penalty : penalties) {
      penalty.PenaltyType__c = type;
      penalty.Status__c = status;
    }
    insert penalties;
    return penalties;
  }

  private static void approveAll(List<Penalty__c> penalties) {
    for (Penalty__c penalty : penalties) {
      penalty.Status__c = LogisticsNotifyService.PENALTY_STATUS_APPROVED;
    }
    update penalties;
  }

  private static Integer countLogs(String status) {
    return [
      SELECT COUNT()
      FROM IntegrationLog__c
      WHERE Status__c = :status
      WITH SYSTEM_MODE
    ];
  }
}
