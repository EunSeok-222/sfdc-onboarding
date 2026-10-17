/* ======================================================================================
 * @description : 점검 결과 항목 트리거 핸들러. 이벤트별로 스냅샷 복사(BR-11)와 미흡 판정(BR-03)을 부른다
 * @testClass   : InspectionResultTriggerHandlerTest
 * @layer       : TriggerHandler
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — insert: 스냅샷 → 미흡 순서 고정, update: 미흡만(D1)
 * ======================================================================================
 *  @see         : InspectionResult.trigger, InspectionResultService.cls
 * ======================================================================================*/
public with sharing class InspectionResultTriggerHandler {
  /**
   * @description : before insert — 템플릿 스냅샷을 복사한 뒤 미흡을 판정한다.
   * @author      : 이은석(Kai) | 2026.10.18
   * @param newResults Trigger.new
   **/
  public void beforeInsert(List<InspectionResult__c> newResults) {
    // WARN: 순서 고정 — 배점(MaxScore__c)을 스냅샷으로 먼저 채워야 미흡을 판정할 수 있다
    InspectionResultService.copyTemplateSnapshots(newResults);
    InspectionResultService.applyDeficiency(newResults);
  }

  /**
   * @description : before update — 미흡만 다시 판정한다. 스냅샷은 복사하지 않는다(BR-11).
   * @author      : 이은석(Kai) | 2026.10.18
   * @param newResults Trigger.new
   **/
  public void beforeUpdate(List<InspectionResult__c> newResults) {
    // NOTE: 템플릿을 나중에 고쳐도 과거 결과는 당시 항목 · 배점을 유지한다. 템플릿을 잘못 골랐으면 삭제 후 다시 만든다
    InspectionResultService.applyDeficiency(newResults);
  }
}
