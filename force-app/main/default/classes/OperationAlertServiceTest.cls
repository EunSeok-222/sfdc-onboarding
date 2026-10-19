/* ======================================================================================
 * @description : 「점검 운영 알림」 공통 — 수신자 계산(Manager · 소유자 · 큐 · 비활성) · 발송 · 그룹 조회를 검증한다
 * @testTarget  : OperationAlertService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성
 * ======================================================================================*/
@IsTest
private class OperationAlertServiceTest {
  // 증명: 활성 Manager → Manager, Manager 없음 → 소유자, 비활성 · 큐 · null은 빠진다(SOQL 1번)
  @IsTest
  static void resolveManagerRecipients_managerOwnerOrNone() {
    User manager = TestDataFactory.createRegionManagerUser('알림팀장', true);
    User withManager = TestDataFactory.createSvUser('알림SV1', false);
    withManager.ManagerId = manager.Id;
    User withoutManager = TestDataFactory.createSvUser('알림SV2', false);
    User inactive = TestDataFactory.createSvUser('알림SV3', false);
    inactive.IsActive = false;
    insert new List<User>{ withManager, withoutManager, inactive };
    Id queueId = [
      SELECT Id
      FROM Group
      WHERE Type = 'Queue' AND DeveloperName = 'UnassignedInspection'
    ]
    .Id;

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    Map<Id, Id> recipients = OperationAlertService.resolveManagerRecipients(
      new Set<Id>{
        withManager.Id,
        withoutManager.Id,
        inactive.Id,
        queueId,
        null
      }
    );
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    Assert.areEqual(
      manager.Id,
      recipients.get(withManager.Id),
      'Manager가 받는다'
    );
    Assert.areEqual(
      withoutManager.Id,
      recipients.get(withoutManager.Id),
      'Manager가 없으면 소유자'
    );
    Assert.isFalse(
      recipients.containsKey(inactive.Id),
      '비활성 소유자(Manager 없음)는 빠진다'
    );
    Assert.isFalse(recipients.containsKey(queueId), '큐 소유는 빠진다');
    Assert.areEqual(1, queriesUsed, 'SOQL 1번');
  }

  // 증명: 수신자가 없는 알림은 건너뛰고, 있는 알림은 보낸다(관리자 실행 — 거부 없음)
  @IsTest
  static void send_skipsEmptyRecipientsAndSends() {
    Account target = TestDataFactory.createFranchises(1, true)[0];
    List<OperationAlertService.Alert> alerts = new List<OperationAlertService.Alert>{
      new OperationAlertService.Alert(
        target.Id,
        '수신자 없음',
        '본문',
        new Set<String>()
      ),
      new OperationAlertService.Alert(
        target.Id,
        '테스트 알림',
        '본문',
        new Set<String>{ UserInfo.getUserId() }
      )
    };

    Test.startTest();
    Integer sent = OperationAlertService.send(alerts);
    Integer nothing = OperationAlertService.send(
      new List<OperationAlertService.Alert>()
    );
    Test.stopTest();

    Assert.areEqual(1, sent, '수신자 있는 1건만 발송');
    Assert.areEqual(0, nothing, '빈 목록은 0건');
    Assert.areEqual(
      1,
      OperationAlertService.attemptedAlerts.size(),
      '시도 1건'
    );
    Assert.areEqual(
      0,
      OperationAlertService.failedAlerts.size(),
      '관리자 실행은 거부 없음'
    );
  }

  // 증명: 배포된 공개 그룹 「연동 알림 수신자」를 찾는다
  @IsTest
  static void integrationAlertGroup_isDeployed() {
    Assert.isNotNull(
      OperationAlertService.getIntegrationAlertGroupId(),
      '그룹 IntegrationAlertRecipients가 있어야 한다'
    );
  }
}
