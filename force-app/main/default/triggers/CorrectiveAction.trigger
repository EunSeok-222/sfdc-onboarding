/* ======================================================================================
 * @description : 시정조치 트리거. 이벤트별로 CorrectiveActionTriggerHandler에 위임만 한다
 * @testClass   : CorrectiveActionTriggerHandlerTest
 * @layer       : Trigger
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — before insert(같은 결과 항목 진행 중 시정조치 중복 차단)
 *  2026.10.19   Kai        Updated     after update 추가 — 지연으로 바뀐 시정조치 알림(점검 소유자의 Manager)
 * ======================================================================================
 *  @note        : 실행 순서 — Before-Save Flow 「기한·재방문 세팅」(UniqueName) → 이 트리거(before) → 저장 →
 *                 After-Save Flow 「점검 시정중 전환」(CorrectiveAction_AfterSave). 여기서 막히면 After-Save Flow는 돌지 않는다
 * ======================================================================================*/
trigger CorrectiveAction on CorrectiveAction__c(before insert, after update) {
  CorrectiveActionTriggerHandler handler = new CorrectiveActionTriggerHandler();

  switch on Trigger.operationType {
    when BEFORE_INSERT {
      handler.beforeInsert(Trigger.new);
    }
    when AFTER_UPDATE {
      handler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
  }
}
