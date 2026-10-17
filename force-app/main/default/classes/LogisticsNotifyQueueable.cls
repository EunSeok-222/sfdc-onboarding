/* ======================================================================================
 * @description : 물류 통보(IF-001) 대기 로그를 연동 사용자 권한으로 보낸다 — 10건씩, 남으면 즉시 · 재시도는 지연 체인
 * @testClass   : LogisticsNotifyQueueableTest
 * @layer       : Queueable
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.16   Kai        Created     최초 작성 — 대기 로그 처리 위임 · 다음 job 체인(즉시 / 지연 1~10분)
 * ======================================================================================
 *  @see         : LogisticsNotifyEventTriggerHandler.cls, LogisticsNotifyService.cls, 인터페이스 정의서 V1.1 IF-001
 *  @note        : enqueue한 사용자 권한으로 실행된다. 이벤트 트리거의 실행 사용자를 연동 사용자로 지정해(PlatformEventSubscriberConfig)
 *                 콜아웃 주체가 승인자가 아니라 연동 사용자가 되게 한다 — 연동 사용자에게 권한 집합 「물류 연동」 필요
 * ======================================================================================*/
public with sharing class LogisticsNotifyQueueable implements Queueable, Database.AllowsCallouts {
  // NOTE: 지연 Queueable은 최대 10분까지 — 재시도 간격(1 · 5 · 10분)이 그 안에 들어온다
  private static final Integer MAX_DELAY_MINUTES = 10;

  // DESC: 테스트에서 체인 대신 다음 job의 지연(분, 0 = 즉시)을 남겨 Assert한다(아래 enqueueNext 참고)
  @TestVisible
  private static Integer chainedDelayMinutesInTest;

  public void execute(QueueableContext context) {
    LogisticsNotifyService.ProcessResult result = LogisticsNotifyService.processPendingLogs();
    if (result.hasMoreDue) {
      enqueueNext(0);
    } else if (result.nextRetryAt != null) {
      enqueueNext(minutesUntil(result.nextRetryAt));
    }
  }

  private static Integer minutesUntil(Datetime target) {
    Decimal minutes = (target.getTime() - Datetime.now().getTime()) / 60000.0;
    return Math.min(
      Math.max(minutes.round(System.RoundingMode.CEILING).intValue(), 1),
      MAX_DELAY_MINUTES
    );
  }

  // NOTE: Apex 테스트에서는 실행 중인 Queueable 안에서 다음 job을 체인하면 오류가 난다(플랫폼 제약).
  //       테스트일 때만 체인 대신 지연 값을 기록한다 — 운영 동작은 그대로다
  // WARN: job 두 개가 동시에 돌면 같은 로그를 두 번 보낼 수 있다. 물류 시스템이 같은 상관 ID에 200만 돌려줘(멱등성)
  //       출고 제한은 1건으로 유지되지만, 그 로그의 시도 횟수는 한 번 더 늘 수 있다
  private static void enqueueNext(Integer delayMinutes) {
    if (Test.isRunningTest() && System.isQueueable()) {
      chainedDelayMinutesInTest = delayMinutes;
      return;
    }
    if (delayMinutes == 0) {
      System.enqueueJob(new LogisticsNotifyQueueable());
    } else {
      System.enqueueJob(new LogisticsNotifyQueueable(), delayMinutes);
    }
  }
}
