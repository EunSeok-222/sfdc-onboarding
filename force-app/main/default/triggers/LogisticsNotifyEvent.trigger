/* ======================================================================================
 * @description : 물류 통보 이벤트 트리거. LogisticsNotifyEventTriggerHandler에 위임만 한다
 * @testClass   : LogisticsNotifyQueueableTest
 * @layer       : Trigger
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.17   Kai        Created     최초 작성 — after insert(대기 로그 처리 시작)
 * ======================================================================================*/
trigger LogisticsNotifyEvent on LogisticsNotifyEvent__e(after insert) {
  LogisticsNotifyEventTriggerHandler handler = new LogisticsNotifyEventTriggerHandler();

  switch on Trigger.operationType {
    when AFTER_INSERT {
      handler.afterInsert(Trigger.new);
    }
  }
}
