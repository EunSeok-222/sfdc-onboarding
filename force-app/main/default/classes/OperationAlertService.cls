/* ======================================================================================
 * @description : 「점검 운영 알림」(Custom Notification) 발송 공통 — 수신자 계산(Manager · 그룹)과 발송 실패 격리
 * @testClass   : OperationAlertServiceTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — 시정 지연 · 연동 실패 · 불합격 2회 연속 알림이 함께 쓴다
 * ======================================================================================
 *  @see         : CorrectiveActionService.notifyOverdue, LogisticsNotifyService.processPendingLogs, InspectionService
 *  @note        : 알림은 부가 기능이다 — 발송이 실패해도(권한 · 수신자 없음 등) 시정조치 저장 · 연동 결과 기록을 되돌리지 않는다
 * ======================================================================================*/
public with sharing class OperationAlertService {
  public static final String NOTIFICATION_TYPE = 'InspectionOperationAlert';
  public static final String INTEGRATION_ALERT_GROUP = 'IntegrationAlertRecipients';

  // NOTE: Custom Notification 제목 · 본문 길이 한도(250 · 750) — 넘치면 발송이 거부된다
  private static final Integer TITLE_MAX_LENGTH = 250;
  private static final Integer BODY_MAX_LENGTH = 750;

  /**
   * @description : 알림 1건 — 대상 레코드(클릭하면 열린다) · 제목 · 본문 · 수신자(사용자 · 그룹 Id)
   **/
  public class Alert {
    public Id targetId;
    public String title;
    public String body;
    public Set<String> recipientIds;

    public Alert(
      Id targetId,
      String title,
      String body,
      Set<String> recipientIds
    ) {
      this.targetId = targetId;
      this.title = title;
      this.body = body;
      this.recipientIds = recipientIds;
    }
  }

  // NOTE: 테스트가 발송 내용을 확인하는 창구 — Custom Notification은 SOQL로 조회할 수 없다.
  //       시도(누구에게 무엇을)와 실패(플랫폼이 거부)를 나눠 기록한다 — 실행 사용자에 따라 발송 자체가 막힐 수 있다
  @TestVisible
  private static List<Alert> attemptedAlerts = new List<Alert>();
  @TestVisible
  private static List<Alert> failedAlerts = new List<Alert>();

  // PERF: 알림 유형 · 그룹 Id는 트랜잭션당 1번만 조회한다
  private static Id notificationTypeId;
  private static Id integrationGroupId;

  /**
   * @description : 소유자 → 알림 받을 사용자. 활성 Manager가 있으면 Manager, 없으면 활성 소유자 자신.
   *                큐 소유 · 비활성 소유자(Manager도 없음)는 결과에서 빠진다. SOQL 1번.
   * @author      : 이은석(Kai) | 2026.10.19
   * @param ownerIds 레코드 소유자 Id(사용자 · 큐 섞여도 된다)
   * @return Map<Id, Id> 소유자 Id → 수신자 사용자 Id
   **/
  public static Map<Id, Id> resolveManagerRecipients(Set<Id> ownerIds) {
    Map<Id, Id> recipientsByOwnerId = new Map<Id, Id>();
    Set<Id> userIds = new Set<Id>();
    for (Id ownerId : ownerIds) {
      if (ownerId != null && ownerId.getSObjectType() == User.SObjectType) {
        userIds.add(ownerId);
      }
    }
    if (userIds.isEmpty()) {
      return recipientsByOwnerId;
    }
    // NOTE: SYSTEM_MODE — 실행 사용자(배치 · 연동 사용자 등)가 사용자 레코드를 볼 수 있는지와 무관하게 계산한다
    for (User owner : [
      SELECT Id, IsActive, ManagerId, Manager.IsActive
      FROM User
      WHERE Id IN :userIds
      WITH SYSTEM_MODE
    ]) {
      if (owner.ManagerId != null && owner.Manager.IsActive) {
        recipientsByOwnerId.put(owner.Id, owner.ManagerId);
      } else if (owner.IsActive) {
        recipientsByOwnerId.put(owner.Id, owner.Id);
      }
    }
    return recipientsByOwnerId;
  }

  /**
   * @description : 공개 그룹 「연동 알림 수신자」 Id. 그룹이 없으면 null(알림을 보내지 않는다).
   * @author      : 이은석(Kai) | 2026.10.19
   * @return Id 그룹 Id
   **/
  public static Id getIntegrationAlertGroupId() {
    if (integrationGroupId == null) {
      List<Group> groups = [
        SELECT Id
        FROM Group
        WHERE Type = 'Regular' AND DeveloperName = :INTEGRATION_ALERT_GROUP
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      integrationGroupId = groups.isEmpty() ? null : groups[0].Id;
    }
    return integrationGroupId;
  }

  /**
   * @description : 알림을 보낸다. 건마다 따로 보내고, 실패한 건은 디버그 로그만 남긴다(호출한 트랜잭션은 그대로 진행).
   * @author      : 이은석(Kai) | 2026.10.19
   * @param alerts 보낼 알림(수신자 없는 건은 건너뛴다)
   * @return Integer 보낸 건수
   **/
  public static Integer send(List<Alert> alerts) {
    if (alerts == null || alerts.isEmpty()) {
      return 0;
    }
    Id typeId = getNotificationTypeId();
    if (typeId == null) {
      System.debug(
        LoggingLevel.WARN,
        '알림 유형 ' + NOTIFICATION_TYPE + '이 없어 알림을 보내지 않았다'
      );
      return 0;
    }
    Integer sent = 0;
    for (Alert alert : alerts) {
      if (alert.recipientIds == null || alert.recipientIds.isEmpty()) {
        continue;
      }
      attemptedAlerts.add(alert);
      try {
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(typeId);
        notification.setTargetId(alert.targetId);
        notification.setTitle(alert.title.abbreviate(TITLE_MAX_LENGTH));
        notification.setBody(alert.body.abbreviate(BODY_MAX_LENGTH));
        // NOTE: send는 DML · SOQL이 아니다 — 레코드마다 대상이 달라 건별로 보낸다
        notification.send(alert.recipientIds);
        sent++;
      } catch (Exception e) {
        // WARN: 알림 실패가 시정조치 저장 · 연동 결과 기록을 되돌리면 안 된다 — 기록만 남긴다
        failedAlerts.add(alert);
        System.debug(
          LoggingLevel.WARN,
          '알림 발송 실패(' + alert.targetId + '): ' + e.getMessage()
        );
      }
    }
    return sent;
  }

  private static Id getNotificationTypeId() {
    if (notificationTypeId == null) {
      List<CustomNotificationType> types = [
        SELECT Id
        FROM CustomNotificationType
        WHERE DeveloperName = :NOTIFICATION_TYPE
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      notificationTypeId = types.isEmpty() ? null : types[0].Id;
    }
    return notificationTypeId;
  }
}
