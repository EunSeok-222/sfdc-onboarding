/* ======================================================================================
 * @description : 시정조치 트리거 핸들러. 이벤트별 분기만 하고 규칙은 CorrectiveActionService에 둔다
 * @testClass   : CorrectiveActionTriggerHandlerTest
 * @layer       : TriggerHandler
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — before insert 중복 차단(리허설: 같은 미흡 항목에 시정조치 2건)
 * ======================================================================================
 *  @see         : CorrectiveAction.trigger, CorrectiveActionService.cls
 * ======================================================================================*/
public with sharing class CorrectiveActionTriggerHandler {
  /**
   * @description : before insert — 같은 결과 항목에 진행 중(요청 · 지연)인 시정조치가 있으면 막는다.
   * @author      : 이은석(Kai) | 2026.10.19
   * @param newActions Trigger.new
   **/
  public void beforeInsert(List<CorrectiveAction__c> newActions) {
    CorrectiveActionService.blockDuplicateOpenActions(newActions);
  }
}
