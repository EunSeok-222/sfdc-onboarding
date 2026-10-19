/* ======================================================================================
 * @description : 물류 통보 깨우기 스케줄러 — 처리할 차례가 된 로그가 있을 때만 이벤트를 발행하는지 검증한다
 * @testTarget  : LogisticsNotifyWakeUpScheduler, LogisticsNotifyService.wakeUpIfDue
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — 전송대기 · 지난 재시도대기 발행, 미래 재시도대기 · 로그 없음 미발행
 * ======================================================================================
 *  @note        : Test.stopTest()를 부르지 않는다 — 부르면 발행한 이벤트가 전달돼 트리거 → Queueable → 콜아웃까지 돈다.
 *                 여기서는 발행 여부만 본다(처리는 LogisticsNotifyQueueableTest)
 * ======================================================================================*/
@IsTest
private class LogisticsNotifyWakeUpSchedulerTest {
  // 증명: 전송대기 로그가 있으면 발행
  @IsTest
  static void pendingLog_publishesWakeUp() {
    insertLog(LogisticsNotifyService.LOG_STATUS_PENDING, null);

    new LogisticsNotifyWakeUpScheduler().execute(null);

    Assert.isTrue(
      LogisticsNotifyWakeUpScheduler.lastPublished,
      '전송대기가 있으면 깨운다'
    );
  }

  // 증명: 재시도대기는 다음 시도 시각이 지났을 때만 발행
  @IsTest
  static void retryLog_publishesOnlyWhenDue() {
    IntegrationLog__c log = insertLog(
      LogisticsNotifyService.LOG_STATUS_RETRY,
      Datetime.now().addMinutes(30)
    );

    Boolean beforeDue = LogisticsNotifyService.wakeUpIfDue();
    update as system new IntegrationLog__c(
      Id = log.Id,
      NextAttemptAt__c = Datetime.now().addMinutes(-1)
    );
    Boolean afterDue = LogisticsNotifyService.wakeUpIfDue();

    Assert.isFalse(beforeDue, '다음 시도 시각 전이면 깨우지 않는다');
    Assert.isTrue(afterDue, '다음 시도 시각이 지나면 깨운다');
  }

  // 증명: 처리할 로그가 없으면 이벤트를 쌓지 않는다
  @IsTest
  static void noDueLogs_doesNotPublish() {
    insertLog(LogisticsNotifyService.LOG_STATUS_SUCCESS, null);

    new LogisticsNotifyWakeUpScheduler().execute(null);

    Assert.isFalse(
      LogisticsNotifyWakeUpScheduler.lastPublished,
      '성공 로그만 있으면 깨우지 않는다'
    );
  }

  private static IntegrationLog__c insertLog(
    String status,
    Datetime nextAttemptAt
  ) {
    List<Penalty__c> penalties = TestDataFactory.createSupplyRestrictionPenalties(
      TestDataFactory.createFranchises(1, true),
      true
    );
    IntegrationLog__c log = TestDataFactory.createLogisticsNotifyLogs(
      penalties,
      status,
      0,
      false
    )[0];
    log.NextAttemptAt__c = nextAttemptAt;
    insert as system log;
    return log;
  }
}
