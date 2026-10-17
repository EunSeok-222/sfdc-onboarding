/* ======================================================================================
 * @description : 점검 결과 항목 트리거. 이벤트별로 InspectionResultTriggerHandler에 위임만 한다
 * @testClass   : InspectionResultTriggerHandlerTest
 * @layer       : Trigger
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — before insert(스냅샷 복사 → 미흡 판정) · before update(미흡 판정)
 * ======================================================================================*/
trigger InspectionResult on InspectionResult__c(before insert, before update) {
  InspectionResultTriggerHandler handler = new InspectionResultTriggerHandler();

  switch on Trigger.operationType {
    when BEFORE_INSERT {
      handler.beforeInsert(Trigger.new);
    }
    when BEFORE_UPDATE {
      handler.beforeUpdate(Trigger.new);
    }
  }
}
