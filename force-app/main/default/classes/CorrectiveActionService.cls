/* ======================================================================================
 * @description : 시정조치 업무 로직 — 기한 초과 시정조치 지연 표시(BR-05)
 * @testClass   : OverdueCorrectiveActionBatchTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.12   Kai        Created     최초 작성 — markOverdue
 * ======================================================================================
 *  @see         : OverdueCorrectiveActionBatch.cls
 * ======================================================================================*/
public with sharing class CorrectiveActionService {
  public static final String STATUS_REQUESTED = '요청';
  public static final String STATUS_OVERDUE = '지연';

  /**
   * @description : 기한이 지난 '요청' 시정조치를 '지연'으로 바꿔 저장한다. 조건에 맞지 않는 레코드는 건너뛴다.
   * @author      : 이은석(Kai) | 2026.10.12
   * @param correctiveActions Status__c · DueDate__c가 조회된 시정조치
   * @return Integer 지연으로 바꾼 건수
   **/
  public static Integer markOverdue(
    List<CorrectiveAction__c> correctiveActions
  ) {
    List<CorrectiveAction__c> overdueActions = new List<CorrectiveAction__c>();
    Date today = Date.today();

    // NOTE: 배치 쿼리가 이미 걸렀어도 조건을 다시 본다 — LWC 버튼 등 다른 호출자가 아무 목록이나 넘겨도 안전하게
    for (CorrectiveAction__c action : correctiveActions) {
      if (
        action.Status__c == STATUS_REQUESTED &&
        action.DueDate__c != null &&
        action.DueDate__c < today
      ) {
        action.Status__c = STATUS_OVERDUE;
        overdueActions.add(action);
      }
    }

    if (!overdueActions.isEmpty()) {
      update overdueActions; // DML 1번
    }
    return overdueActions.size();
  }
}
