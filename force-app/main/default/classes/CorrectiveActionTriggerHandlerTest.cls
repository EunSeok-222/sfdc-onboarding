/* ======================================================================================
 * @description : 시정조치 트리거 — 같은 결과 항목 진행 중(요청 · 지연) 시정조치 중복 차단을 검증한다
 * @testTarget  : CorrectiveActionTriggerHandler, CorrectiveActionService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — 요청 · 지연 중복 차단, 완료 뒤 재요청 허용, 같은 묶음 중복, 벌크 200
 *  2026.10.19   Kai        Updated     지연 전환 알림 — Manager 수신 · 지연이 아닌 변경 무알림 · 벌크 200
 * ======================================================================================*/
@IsTest
private class CorrectiveActionTriggerHandlerTest {
  private static final Integer BULK_SIZE = 200;

  @TestSetup
  static void setupData() {
    Inspection__c ins = TestDataFactory.createInspections(
      TestDataFactory.createFranchises(1, true),
      1,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    )[0];
    List<InspectionTemplateItem__c> items = TestDataFactory.createTemplateItems(
      BULK_SIZE,
      0,
      10,
      true
    );
    List<Decimal> scores = new List<Decimal>();
    for (Integer i = 0; i < BULK_SIZE; i++) {
      scores.add(5);
    }
    TestDataFactory.createResults(ins, items, scores, true);
  }

  // 증명: 같은 결과 항목에 요청 · 지연 시정조치가 있으면 새 시정조치를 막고 기존 번호를 알려 준다
  @IsTest
  static void openExisting_requestedOrOverdue_blocksNew() {
    List<InspectionResult__c> results = getResults(2);
    insertAction(results[0], CorrectiveActionService.STATUS_REQUESTED);
    insertAction(results[1], CorrectiveActionService.STATUS_OVERDUE);
    Map<Id, String> existingNosByResult = getActionNosByResult();

    Test.startTest();
    List<Database.SaveResult> saved = Database.insert(
      TestDataFactory.createCorrectiveActions(
        results,
        1,
        CorrectiveActionService.STATUS_REQUESTED,
        Date.today().addDays(7),
        false
      ),
      false
    );
    Test.stopTest();

    for (Integer i = 0; i < saved.size(); i++) {
      Assert.isFalse(
        saved[i].isSuccess(),
        '진행 중 시정조치가 있으면 막아야 한다'
      );
      Assert.isTrue(
        saved[i].getErrors()[0]
          .getMessage()
          .startsWith(
            '이 결과 항목에 진행 중인 시정조치가 있습니다: ' +
            existingNosByResult.get(results[i].Id)
          ),
        '기존 번호를 알려 줘야 한다. 실제: ' +
        saved[i].getErrors()[0].getMessage()
      );
    }
  }

  // 증명: 조치완료 · 확인완료 뒤에는 같은 결과 항목으로 다시 요청할 수 있다
  @IsTest
  static void completedExisting_allowsNewRequest() {
    List<InspectionResult__c> results = getResults(2);
    insertAction(results[0], '조치완료');
    insertAction(results[1], '확인완료');

    Test.startTest();
    List<Database.SaveResult> saved = Database.insert(
      TestDataFactory.createCorrectiveActions(
        results,
        1,
        CorrectiveActionService.STATUS_REQUESTED,
        Date.today().addDays(7),
        false
      ),
      false
    );
    Test.stopTest();

    for (Database.SaveResult result : saved) {
      Assert.isTrue(
        result.isSuccess(),
        '완료 뒤 재요청은 저장된다: ' + result.getErrors()
      );
    }
  }

  // 증명: 같은 저장 묶음에 같은 결과 항목이 두 번 오면 첫 행만 저장된다
  @IsTest
  static void sameBatch_secondRowBlocked() {
    List<InspectionResult__c> results = getResults(1);

    Test.startTest();
    List<Database.SaveResult> saved = Database.insert(
      TestDataFactory.createCorrectiveActions(
        results,
        2,
        CorrectiveActionService.STATUS_REQUESTED,
        Date.today().addDays(7),
        false
      ),
      false
    );
    Test.stopTest();

    Assert.isTrue(
      saved[0].isSuccess(),
      '첫 행은 저장된다: ' + saved[0].getErrors()
    );
    Assert.isFalse(saved[1].isSuccess(), '두 번째 행은 막혀야 한다');
    Assert.isTrue(
      saved[1].getErrors()[0].getMessage().contains('같이 저장하는 다른 행'),
      '같은 묶음 중복 문구. 실제: ' + saved[1].getErrors()[0].getMessage()
    );
  }

  // 증명: 서로 다른 결과 항목 200개에 한 번에 넣으면 모두 저장되고, 쿼리 수가 건수에 비례하지 않는다
  @IsTest
  static void bulk200_differentResults_allSaved() {
    List<InspectionResult__c> results = getResults(BULK_SIZE);

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    insert TestDataFactory.createCorrectiveActions(
      results,
      1,
      CorrectiveActionService.STATUS_REQUESTED,
      Date.today().addDays(7),
      false
    );
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    Assert.areEqual(
      BULK_SIZE,
      [
        SELECT COUNT()
        FROM CorrectiveAction__c
        WHERE InspectionResult__c IN :results
      ],
      '200건 모두 저장'
    );
    // NOTE: 중복 검사 1번 + Before-Save Flow(기준 조회) · After-Save Flow(점검 상태) · 점검 트리거 — 모두 일괄 처리라 몇 번 안에 끝난다
    Assert.isTrue(
      queriesUsed <= 10,
      '200건이어도 쿼리 수가 건수에 비례하면 안 된다. 실제: ' + queriesUsed
    );
  }

  // ---------------------------------------------------------------- 지연 알림

  // 증명: 지연으로 바뀌면 점검 소유자의 Manager에게 알린다 — 대상 = 시정조치, 제목에 가맹점, 본문에 번호 · 기한
  @IsTest
  static void overdueChange_alertsInspectionOwnersManager() {
    User manager = TestDataFactory.createRegionManagerUser(
      '지연알림팀장',
      true
    );
    User sv = TestDataFactory.createSvUser('지연알림SV', false);
    sv.ManagerId = manager.Id;
    insert sv;
    Inspection__c ins = [
      SELECT Id, Franchise__r.Name
      FROM Inspection__c
      LIMIT 1
    ];
    update new Inspection__c(Id = ins.Id, OwnerId = sv.Id);
    insertAction(getResults(1)[0], CorrectiveActionService.STATUS_REQUESTED);
    CorrectiveAction__c action = [
      SELECT Id, Name
      FROM CorrectiveAction__c
      LIMIT 1
    ];

    Test.startTest();
    update new CorrectiveAction__c(
      Id = action.Id,
      Status__c = CorrectiveActionService.STATUS_OVERDUE
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      OperationAlertService.attemptedAlerts.size(),
      '지연 전환 1건 → 알림 1건'
    );
    OperationAlertService.Alert alert = OperationAlertService.attemptedAlerts[0];
    Assert.areEqual(action.Id, alert.targetId, '대상 = 시정조치');
    Assert.isTrue(
      alert.recipientIds.contains(manager.Id),
      '수신자 = 점검 소유자의 Manager'
    );
    Assert.isTrue(
      alert.title.contains(ins.Franchise__r.Name),
      '제목에 가맹점: ' + alert.title
    );
    Assert.isTrue(
      alert.body.contains(action.Name) && alert.body.contains('기한'),
      '본문에 번호 · 기한: ' + alert.body
    );
  }

  // 증명: 지연이 아닌 상태로 바뀌거나 이미 지연인 건을 다시 저장하면 알리지 않는다
  @IsTest
  static void nonOverdueChanges_noAlert() {
    List<InspectionResult__c> results = getResults(2);
    insertAction(results[0], CorrectiveActionService.STATUS_REQUESTED);
    insertAction(results[1], CorrectiveActionService.STATUS_OVERDUE);
    List<CorrectiveAction__c> actions = [
      SELECT Id, Status__c
      FROM CorrectiveAction__c
      ORDER BY Name
    ];

    Test.startTest();
    actions[0].Status__c = '조치완료';
    actions[1].DueDate__c = Date.today().addDays(10);
    update actions;
    Test.stopTest();

    Assert.areEqual(
      0,
      OperationAlertService.attemptedAlerts.size(),
      '지연 전환이 아니면 알림 없음'
    );
  }

  // 증명: 200건이 한 번에 지연으로 바뀌어도 건마다 알림 1건, 쿼리 수는 건수와 무관하다
  @IsTest
  static void bulk200Overdue_alertEachConstantQueries() {
    List<CorrectiveAction__c> actions = TestDataFactory.createCorrectiveActions(
      getResults(BULK_SIZE),
      1,
      CorrectiveActionService.STATUS_REQUESTED,
      Date.today().addDays(7),
      true
    );

    // NOTE: Id · 상태만 담아 update — 팩토리가 돌려준 레코드에는 결과 항목(Master-Detail, 수정 불가)이 들어 있다
    List<CorrectiveAction__c> overdue = new List<CorrectiveAction__c>();
    for (CorrectiveAction__c action : actions) {
      overdue.add(
        new CorrectiveAction__c(
          Id = action.Id,
          Status__c = CorrectiveActionService.STATUS_OVERDUE
        )
      );
    }

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    update overdue;
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    Assert.areEqual(
      BULK_SIZE,
      OperationAlertService.attemptedAlerts.size(),
      '200건 → 알림 200건'
    );
    // NOTE: 맥락 조회 1 + 수신자(User) 1 + 알림 유형 1
    Assert.isTrue(
      queriesUsed <= 3,
      '쿼리 수가 건수와 무관해야 한다. 실제: ' + queriesUsed
    );
  }

  // ---------------------------------------------------------------- 도우미

  private static List<InspectionResult__c> getResults(Integer count) {
    return [SELECT Id FROM InspectionResult__c ORDER BY Name LIMIT :count];
  }

  private static void insertAction(InspectionResult__c result, String status) {
    insert new CorrectiveAction__c(
      InspectionResult__c = result.Id,
      Status__c = status,
      DueDate__c = Date.today().addDays(3)
    );
  }

  private static Map<Id, String> getActionNosByResult() {
    Map<Id, String> nosByResult = new Map<Id, String>();
    for (CorrectiveAction__c action : [
      SELECT Name, InspectionResult__c
      FROM CorrectiveAction__c
    ]) {
      nosByResult.put(action.InspectionResult__c, action.Name);
    }
    return nosByResult;
  }
}
