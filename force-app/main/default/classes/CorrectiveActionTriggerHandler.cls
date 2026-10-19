/* ======================================================================================
 * @description : 시정조치 트리거 핸들러. 이벤트별 분기만 하고 규칙은 CorrectiveActionService에 둔다
 * @testClass   : CorrectiveActionTriggerHandlerTest
 * @layer       : TriggerHandler
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — before insert 중복 차단(리허설: 같은 미흡 항목에 시정조치 2건)
 *  2026.10.19   Kai        Updated     after update — 지연 전환 알림
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

  /**
   * @description : after update — 「지연」으로 바뀐 시정조치를 점검 소유자의 Manager에게 알린다(배치 · 수동 변경 모두).
   * @author      : 이은석(Kai) | 2026.10.19
   * @param newActions     Trigger.new
   * @param oldActionsById Trigger.oldMap
   **/
  public void afterUpdate(
    List<CorrectiveAction__c> newActions,
    Map<Id, CorrectiveAction__c> oldActionsById
  ) {
    CorrectiveActionService.notifyOverdue(newActions, oldActionsById);
  }
}
