/* ======================================================================================
 * @description : 시정조치 업무 로직 — 기한 초과 시정조치 지연 표시(BR-05) · 진행 중 시정조치 중복 차단
 * @testClass   : OverdueCorrectiveActionBatchTest, CorrectiveActionTriggerHandlerTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.12   Kai        Created     최초 작성 — markOverdue
 *  2026.10.19   Kai        Updated     blockDuplicateOpenActions 추가 — 같은 결과 항목에 요청 · 지연 시정조치 중복 차단
 *  2026.10.19   Kai        Updated     notifyOverdue 추가 — 지연으로 바뀐 시정조치를 점검 소유자의 Manager에게 알림
 * ======================================================================================
 *  @see         : OverdueCorrectiveActionBatch.cls, CorrectiveActionTriggerHandler.cls
 *  @note        : 시정조치는 결과 항목의 Master-Detail 자식(Controlled by Parent)이라, 저장하는 사용자는 같은 결과 항목의
 *                 다른 시정조치도 볼 수 있다 — 중복 조회에 without sharing이 필요 없다
 * ======================================================================================*/
public with sharing class CorrectiveActionService {
  public static final String STATUS_REQUESTED = '요청';
  public static final String STATUS_OVERDUE = '지연';

  // DESC: 진행 중 = 요청 · 지연. 조치완료 · 확인완료 뒤에는 같은 항목으로 다시 요청할 수 있다
  private static final Set<String> OPEN_STATUSES = new Set<String>{
    STATUS_REQUESTED,
    STATUS_OVERDUE
  };

  /**
   * @description : 같은 결과 항목에 진행 중(요청 · 지연)인 시정조치가 DB나 같은 저장 묶음에 있으면 막는다.
   *                새 시정조치 자신이 진행 중 상태일 때만 검사한다(완료 상태로 바로 넣는 이관 데이터 등은 통과).
   * @author      : 이은석(Kai) | 2026.10.19
   * @param newActions Trigger.new (before insert)
   **/
  public static void blockDuplicateOpenActions(
    List<CorrectiveAction__c> newActions
  ) {
    List<CorrectiveAction__c> targets = new List<CorrectiveAction__c>();
    Set<Id> resultIds = new Set<Id>();
    for (CorrectiveAction__c action : newActions) {
      if (
        action.InspectionResult__c == null ||
        !OPEN_STATUSES.contains(action.Status__c)
      ) {
        continue;
      }
      targets.add(action);
      resultIds.add(action.InspectionResult__c);
    }
    if (targets.isEmpty()) {
      return;
    }

    // PERF: SOQL 1번 — 결과 항목 → 진행 중 시정조치 번호
    Map<Id, String> openNosByResultId = new Map<Id, String>();
    for (CorrectiveAction__c existing : [
      SELECT Name, InspectionResult__c
      FROM CorrectiveAction__c
      WHERE InspectionResult__c IN :resultIds AND Status__c IN :OPEN_STATUSES
      WITH SYSTEM_MODE
      ORDER BY Name
    ]) {
      if (!openNosByResultId.containsKey(existing.InspectionResult__c)) {
        openNosByResultId.put(existing.InspectionResult__c, existing.Name);
      }
    }

    Set<Id> resultIdsInBatch = new Set<Id>();
    for (CorrectiveAction__c action : targets) {
      if (openNosByResultId.containsKey(action.InspectionResult__c)) {
        action.addError(
          duplicateMessage(openNosByResultId.get(action.InspectionResult__c))
        );
      } else if (!resultIdsInBatch.add(action.InspectionResult__c)) {
        action.addError(duplicateMessage('같이 저장하는 다른 행'));
      }
    }
  }

  private static String duplicateMessage(String existing) {
    return '이 결과 항목에 진행 중인 시정조치가 있습니다: ' +
      existing +
      ' (조치완료 · 확인완료 뒤에 다시 요청할 수 있습니다)';
  }

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

  /**
   * @description : 「지연」으로 바뀐 시정조치마다 점검 소유자의 Manager(없으면 소유자)에게 「점검 운영 알림」을 보낸다.
   *                문구에 가맹점 · 점검 항목 · 기한. SOQL은 건수와 무관하게 2번(시정조치 맥락 1 + 수신자 1).
   * @author      : 이은석(Kai) | 2026.10.19
   * @param newActions     Trigger.new (after update)
   * @param oldActionsById Trigger.oldMap
   **/
  public static void notifyOverdue(
    List<CorrectiveAction__c> newActions,
    Map<Id, CorrectiveAction__c> oldActionsById
  ) {
    Set<Id> overdueIds = new Set<Id>();
    for (CorrectiveAction__c action : newActions) {
      if (
        action.Status__c == STATUS_OVERDUE &&
        oldActionsById.get(action.Id).Status__c != STATUS_OVERDUE
      ) {
        overdueIds.add(action.Id);
      }
    }
    if (overdueIds.isEmpty()) {
      return;
    }

    // DESC: 점검 소유자는 결과 항목 → 점검 2단 위라 Trigger.new에 없다 — 맥락(수식 필드)과 함께 1번에 조회
    List<CorrectiveAction__c> overdueActions = [
      SELECT
        Id,
        Name,
        DueDate__c,
        fmFranchiseName__c,
        fmItemName__c,
        InspectionResult__r.Inspection__r.OwnerId
      FROM CorrectiveAction__c
      WHERE Id IN :overdueIds
      WITH SYSTEM_MODE
    ];
    Set<Id> ownerIds = new Set<Id>();
    for (CorrectiveAction__c action : overdueActions) {
      ownerIds.add(action.InspectionResult__r.Inspection__r.OwnerId);
    }
    Map<Id, Id> recipientsByOwnerId = OperationAlertService.resolveManagerRecipients(
      ownerIds
    );

    List<OperationAlertService.Alert> alerts = new List<OperationAlertService.Alert>();
    for (CorrectiveAction__c action : overdueActions) {
      Id recipientId = recipientsByOwnerId.get(
        action.InspectionResult__r.Inspection__r.OwnerId
      );
      if (recipientId == null) {
        continue; // NOTE: 큐 소유(미배정) · 비활성 소유자 — 받을 사람이 없다
      }
      alerts.add(
        new OperationAlertService.Alert(
          action.Id,
          '시정조치 지연 — ' + action.fmFranchiseName__c,
          action.Name +
            ' · ' +
            action.fmItemName__c +
            ' · 기한 ' +
            formatDate(action.DueDate__c) +
            '이 지났습니다.',
          new Set<String>{ recipientId }
        )
      );
    }
    OperationAlertService.send(alerts);
  }

  private static String formatDate(Date value) {
    return value == null
      ? '(없음)'
      : String.valueOf(value.month()).leftPad(2, '0') +
        '.' +
        String.valueOf(value.day()).leftPad(2, '0');
  }
}
