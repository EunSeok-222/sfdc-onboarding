/* ======================================================================================
 * @description : 페널티 트리거. 이벤트별로 PenaltyTriggerHandler에 위임만 한다
 * @testClass   : PenaltyTriggerHandlerTest, PenaltyServiceTest
 * @layer       : Trigger
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.16   Kai        Created     최초 작성 — after update(공급 제한 승인 → 물류 통보)
 *  2026.10.19   Kai        Updated     before insert · before update 추가 — 공급 제한 기간 자동 · 중복 차단
 * ======================================================================================*/
trigger Penalty on Penalty__c(before insert, before update, after update) {
  PenaltyTriggerHandler handler = new PenaltyTriggerHandler();

  switch on Trigger.operationType {
    when BEFORE_INSERT {
      handler.beforeInsert(Trigger.new);
    }
    when BEFORE_UPDATE {
      handler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
    when AFTER_UPDATE {
      handler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
  }
}
