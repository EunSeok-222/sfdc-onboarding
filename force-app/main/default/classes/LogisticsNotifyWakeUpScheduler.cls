/* ======================================================================================
 * @description : 물류 통보 대기 로그 깨우기 — 매시 정각, 처리할 차례가 된 로그가 있을 때만 깨우기 이벤트 발행
 * @testClass   : LogisticsNotifyWakeUpSchedulerTest
 * @layer       : Batch
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — scripts/apex/logisticsNotifyWakeUp.apex 수동 실행을 자동화
 * ======================================================================================
 *  @see         : LogisticsNotifyService.wakeUpIfDue, LogisticsNotifyEvent.trigger
 *  @note        : 등록(관리자, 배포 후 수작업 — scripts/post-deploy/README.md) —
 *                 System.schedule('물류 통보 깨우기', LogisticsNotifyWakeUpScheduler.CRON_HOURLY,
 *                 new LogisticsNotifyWakeUpScheduler());  (매시 0분)
 *                 이벤트를 받은 트리거는 구독자 설정대로 연동 사용자 권한으로 처리한다 — 등록자는 발행만 한다
 * ======================================================================================*/
public with sharing class LogisticsNotifyWakeUpScheduler implements Schedulable {
  public static final String CRON_HOURLY = '0 0 * * * ?';

  // NOTE: 테스트에서 발행 여부를 확인하는 창구
  @TestVisible
  private static Boolean lastPublished;

  public void execute(SchedulableContext sc) {
    lastPublished = LogisticsNotifyService.wakeUpIfDue();
  }
}
