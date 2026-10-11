/* ======================================================================================
 * @description : 점검 트리거. 이벤트를 받아 InspectionTriggerHandler로 넘기기만 한다
 * @testClass   : InspectionTriggerHandlerTest
 * @layer       : Trigger
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.11   Kai        Created     최초 작성 (뼈대)
 * ======================================================================================*/
trigger Inspection on Inspection__c(
  before update,
  after insert,
  after update,
  after delete,
  after undelete
) {
  // NOTE: before insert 제외 — 새 점검은 결과 항목이 없어 판정할 값이 없고, 상태 검증을 걸면 이관 데이터('종료' 상태)가 막힘
  InspectionTriggerHandler handler = new InspectionTriggerHandler();

  switch on Trigger.operationType {
    when BEFORE_UPDATE {
      handler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
    when AFTER_INSERT {
      handler.afterInsert(Trigger.new);
    }
    when AFTER_UPDATE {
      handler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
    when AFTER_DELETE {
      handler.afterDelete(Trigger.old);
    }
    when AFTER_UNDELETE {
      handler.afterUndelete(Trigger.new);
    }
  }
}
