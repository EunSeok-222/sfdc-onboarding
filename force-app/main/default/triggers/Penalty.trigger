/* ======================================================================================
 * @description : 페널티 트리거. 이벤트별로 PenaltyTriggerHandler에 위임만 한다
 * @testClass   : PenaltyTriggerHandlerTest
 * @layer       : Trigger
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.16   Kai        Created     최초 작성 — after update(공급 제한 승인 → 물류 통보)
 * ======================================================================================*/
trigger Penalty on Penalty__c(after update) {
  PenaltyTriggerHandler handler = new PenaltyTriggerHandler();

  switch on Trigger.operationType {
    when AFTER_UPDATE {
      handler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
  }
}
