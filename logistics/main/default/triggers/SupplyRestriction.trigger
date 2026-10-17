/* ======================================================================================
 * @description : 출고 제한 트리거. 이벤트별로 SupplyRestrictionTriggerHandler에 위임만 한다
 * @testClass   : SupplyRestrictionResultQueueableTest
 * @layer       : Trigger
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — before update(처리 일시) · after update(IF-004 회신 enqueue)
 * ======================================================================================
 *  @note        : 가상 물류 시스템(hankki-logistics org) 소스다. kai-dev에는 배포하지 않는다
 * ======================================================================================*/
trigger SupplyRestriction on SupplyRestriction__c(before update, after update) {
  SupplyRestrictionTriggerHandler handler = new SupplyRestrictionTriggerHandler();

  switch on Trigger.operationType {
    when BEFORE_UPDATE {
      handler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
    when AFTER_UPDATE {
      handler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
  }
}
