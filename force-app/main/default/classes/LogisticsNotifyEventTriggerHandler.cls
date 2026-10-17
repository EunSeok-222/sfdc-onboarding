/* ======================================================================================
 * @description : 물류 통보 이벤트 트리거 핸들러. 대기 로그 처리 Queueable을 1개 넣는다
 * @testClass   : LogisticsNotifyQueueableTest
 * @layer       : TriggerHandler
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.17   Kai        Created     최초 작성 — IF-001 이벤트 수신 시 LogisticsNotifyQueueable enqueue
 * ======================================================================================
 *  @see         : LogisticsNotifyEvent.trigger, LogisticsNotifyQueueable.cls
 *  @note        : 이벤트 트리거는 PlatformEventSubscriberConfig로 지정한 연동 사용자 권한으로 돈다(배포 후 수작업).
 *                 지정하지 않으면 Automated Process 사용자로 돌아 Named Credential 주체 접근이 없어 콜아웃이 실패한다
 * ======================================================================================*/
public with sharing class LogisticsNotifyEventTriggerHandler {
  /**
   * @description : after insert — IF-001 이벤트가 한 건이라도 있으면 Queueable을 1개 넣는다.
   * @author      : 이은석(Kai) | 2026.10.17
   * @param events Trigger.new
   **/
  public void afterInsert(List<LogisticsNotifyEvent__e> events) {
    // DESC: 이벤트는 "대기 로그가 생겼다"는 신호일 뿐이다 — 몇 건이 와도 job 1개가 대기 로그를 모두 찾아 처리한다
    for (LogisticsNotifyEvent__e event : events) {
      if (event.InterfaceId__c == LogisticsNotifyService.INTERFACE_ID) {
        System.enqueueJob(new LogisticsNotifyQueueable());
        return;
      }
    }
  }
}
