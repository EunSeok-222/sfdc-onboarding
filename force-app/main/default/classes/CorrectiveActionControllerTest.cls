/* ======================================================================================
 * @description : 점검별 시정조치 목록 조회(getByInspection)를 검증하는 테스트 클래스
 * @testTarget  : CorrectiveActionController
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 (정렬 · 점검 격리 · null · 벌크 200건 · SV runAs)
 *  2026.10.14   Kai        Updated     getDeficientResults 테스트 추가 (미흡 항목만 · 필수 항목 우선)
 *  2026.10.19   Kai        Updated     벌크 데이터를 결과 항목 200개 × 시정조치 1건으로 변경 — 같은 항목 진행 중 시정조치 중복 차단 반영
 * ======================================================================================*/
@IsTest
private class CorrectiveActionControllerTest {
  private static final String STATUS_REQUESTED = '요청';
  // NOTE: InspectionNo__c는 Unique — TestDataFactory 자동 번호(TEST-0000…)는 트랜잭션마다 0부터 다시 시작하므로
  //       @TestSetup 데이터와 테스트 메서드에서 만든 데이터가 겹치지 않게 직접 지정한다
  private static final String TARGET_INSPECTION_NO = 'TEST-CA-TARGET';
  private static final String OTHER_INSPECTION_NO = 'TEST-CA-OTHER';
  private static final String BULK_INSPECTION_NO = 'TEST-CA-BULK';
  private static final String ORDER_INSPECTION_NO = 'TEST-CA-ORDER';
  private static final String SV_OWNER_LAST_NAME = 'CA테스트SV담당';
  private static final String SV_OTHER_LAST_NAME = 'CA테스트SV타담당';

  // DESC: SV 2명이 점검을 1건씩 소유한다. 대상 점검 = 결과 항목 2건 × 조치 1건(기한 +7일 · +3일),
  //       타 SV 점검 = 결과 항목 2건 × 조치 1건(기한 +1일). 대상보다 기한이 빠른 조치가 섞여 있어야 격리 · 정렬이 함께 검증된다
  @TestSetup
  static void setupData() {
    User svOwner = TestDataFactory.createSvUser(SV_OWNER_LAST_NAME, false);
    User svOther = TestDataFactory.createSvUser(SV_OTHER_LAST_NAME, false);
    // NOTE: 역할(UserRoleId)이 없는 사용자라 같은 트랜잭션에서 업무 데이터를 넣어도 Mixed DML 오류가 나지 않는다
    insert new List<User>{ svOwner, svOther };

    List<Account> franchises = TestDataFactory.createFranchises(2, true);
    List<InspectionTemplateItem__c> templateItems = TestDataFactory.createTemplateItems(
      2,
      1,
      10,
      true
    );

    List<Inspection__c> inspections = TestDataFactory.createInspections(
      franchises,
      1,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      false
    );
    Inspection__c target = inspections[0];
    target.InspectionNo__c = TARGET_INSPECTION_NO;
    target.OwnerId = svOwner.Id;
    Inspection__c other = inspections[1];
    other.InspectionNo__c = OTHER_INSPECTION_NO;
    other.OwnerId = svOther.Id;
    insert inspections;

    List<InspectionResult__c> targetResults = TestDataFactory.createResults(
      target,
      templateItems,
      new List<Decimal>{ 10, 5 },
      false
    );
    List<InspectionResult__c> otherResults = TestDataFactory.createResults(
      other,
      templateItems,
      new List<Decimal>{ 5, 5 },
      false
    );
    List<InspectionResult__c> results = new List<InspectionResult__c>();
    results.addAll(targetResults);
    results.addAll(otherResults);
    insert results;

    List<CorrectiveAction__c> targetActions = TestDataFactory.createCorrectiveActions(
      targetResults,
      1,
      STATUS_REQUESTED,
      null,
      false
    );
    // DESC: 첫 결과 항목의 조치가 기한이 더 늦다 → 정렬이 생성 순서가 아니라 기한 기준인지 확인할 수 있다
    targetActions[0].DueDate__c = Date.today().addDays(7);
    targetActions[1].DueDate__c = Date.today().addDays(3);
    List<CorrectiveAction__c> otherActions = TestDataFactory.createCorrectiveActions(
      otherResults,
      1,
      STATUS_REQUESTED,
      Date.today().addDays(1),
      false
    );
    List<CorrectiveAction__c> actions = new List<CorrectiveAction__c>();
    actions.addAll(targetActions);
    actions.addAll(otherActions);
    insert actions;
  }

  // 대상 점검의 조치 2건이 기한 오름차순으로 오고, 결과 항목 정보도 함께 온다
  @IsTest
  static void getByInspection_returnsActionsInDueDateOrder() {
    Id targetId = getInspectionId(TARGET_INSPECTION_NO);

    Test.startTest();
    List<CorrectiveAction__c> actions = CorrectiveActionController.getByInspection(
      targetId
    );
    Test.stopTest();

    Assert.areEqual(2, actions.size(), '대상 점검의 조치는 2건이어야 한다');
    Assert.areEqual(
      Date.today().addDays(3),
      actions[0].DueDate__c,
      '기한이 빠른 조치(+3일)가 첫 건이어야 한다'
    );
    Assert.areEqual(
      Date.today().addDays(7),
      actions[1].DueDate__c,
      '기한이 늦은 조치(+7일)가 두 번째여야 한다'
    );
    Assert.isNotNull(
      actions[0].InspectionResult__r.ItemName__c,
      '결과 항목의 항목명이 함께 조회되어야 한다'
    );
  }

  // 다른 점검의 조치는 기한이 더 빨라도 섞이지 않는다
  @IsTest
  static void getByInspection_excludesOtherInspections() {
    Id targetId = getInspectionId(TARGET_INSPECTION_NO);
    Set<Id> otherActionIds = new Map<Id, CorrectiveAction__c>(
        [
          SELECT Id
          FROM CorrectiveAction__c
          WHERE
            InspectionResult__r.Inspection__r.InspectionNo__c = :OTHER_INSPECTION_NO
        ]
      )
      .keySet();
    Assert.areEqual(
      2,
      otherActionIds.size(),
      '전제: 타 점검의 조치가 2건 있어야 한다'
    );

    Test.startTest();
    List<CorrectiveAction__c> actions = CorrectiveActionController.getByInspection(
      targetId
    );
    Test.stopTest();

    Assert.areEqual(2, actions.size(), '대상 점검의 조치 2건만 와야 한다');
    for (CorrectiveAction__c action : actions) {
      Assert.isFalse(
        otherActionIds.contains(action.Id),
        '다른 점검의 조치가 섞이면 안 된다: ' + action.Name
      );
    }
  }

  // inspectionId가 null이면 예외 없이 빈 목록을 돌려준다
  @IsTest
  static void getByInspection_nullId_returnsEmptyList() {
    Test.startTest();
    List<CorrectiveAction__c> actions = CorrectiveActionController.getByInspection(
      null
    );
    Integer queriesUsed = Limits.getQueries();
    Test.stopTest();

    Assert.isNotNull(actions, 'null이 아니라 빈 목록이어야 한다');
    Assert.isTrue(actions.isEmpty(), 'inspectionId가 null이면 0건이어야 한다');
    Assert.areEqual(0, queriesUsed, 'null이면 SOQL을 실행하지 않아야 한다');
  }

  // 결과 항목 50건 × 조치 4건 = 200건이어도 SOQL 1번으로 전부 조회한다
  @IsTest
  static void getByInspection_bulk200_usesOneQuery() {
    // WARN: createFranchises를 다시 부르면 사업자번호가 @TestSetup 가맹점과 같은 값(인덱스 0부터)으로 만들어져
    //       Duplicate Rule(사업자번호 일치)에 막힌다 → @TestSetup 가맹점을 재사용한다
    Account franchise = new Account(
      Id = [
        SELECT Franchise__c
        FROM Inspection__c
        WHERE InspectionNo__c = :TARGET_INSPECTION_NO
      ]
      .Franchise__c
    );
    // NOTE: 같은 결과 항목에는 진행 중 시정조치를 1건만 둘 수 있다(중복 차단) — 결과 항목 200개에 1건씩
    List<InspectionTemplateItem__c> templateItems = TestDataFactory.createTemplateItems(
      200,
      0,
      10,
      true
    );
    Inspection__c bulkInspection = TestDataFactory.createInspections(
      new List<Account>{ franchise },
      1,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      false
    )[0];
    bulkInspection.InspectionNo__c = BULK_INSPECTION_NO;
    insert bulkInspection;

    List<Decimal> scores = new List<Decimal>();
    for (Integer i = 0; i < templateItems.size(); i++) {
      scores.add(5);
    }
    List<InspectionResult__c> results = TestDataFactory.createResults(
      bulkInspection,
      templateItems,
      scores,
      true
    );
    TestDataFactory.createCorrectiveActions(
      results,
      1,
      STATUS_REQUESTED,
      Date.today().addDays(3),
      true
    );

    Test.startTest();
    List<CorrectiveAction__c> actions = CorrectiveActionController.getByInspection(
      bulkInspection.Id
    );
    Integer queriesUsed = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(200, actions.size(), '조치 200건이 전부 조회되어야 한다');
    Assert.areEqual(1, queriesUsed, '건수와 무관하게 SOQL은 1번이어야 한다');
  }

  // SV는 자기 소유 점검의 조치만 본다. 타 SV 소유 점검을 Id로 직접 물어도 0건
  @IsTest
  static void getByInspection_runAsSv_returnsOnlyOwnInspectionActions() {
    User svOwner = [
      SELECT Id
      FROM User
      WHERE
        LastName = :SV_OWNER_LAST_NAME
        AND Profile.Name = :TestDataFactory.PROFILE_SV
      LIMIT 1
    ];
    Id targetId = getInspectionId(TARGET_INSPECTION_NO);
    Id otherId = getInspectionId(OTHER_INSPECTION_NO);

    List<CorrectiveAction__c> ownActions;
    List<CorrectiveAction__c> otherActions;
    Test.startTest();
    System.runAs(svOwner) {
      ownActions = CorrectiveActionController.getByInspection(targetId);
      otherActions = CorrectiveActionController.getByInspection(otherId);
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      ownActions.size(),
      'SV는 자기 소유 점검의 조치 2건을 모두 봐야 한다'
    );
    Assert.areEqual(
      0,
      otherActions.size(),
      'SV는 타 SV 소유 점검의 조치를 볼 수 없어야 한다 (with sharing · USER_MODE)'
    );
  }

  // ---------------------------------------------------------------- getDeficientResults

  // 대상 점검의 결과 항목 2건 중 미흡(만점 미만)인 1건만 온다
  @IsTest
  static void getDeficientResults_returnsDeficientOnly() {
    Id targetId = getInspectionId(TARGET_INSPECTION_NO);
    // DESC: @TestSetup에서 점수 10(만점) · 5를 넣었다 → TestDataFactory가 5점 항목만 미흡으로 세팅
    InspectionResult__c deficient = [
      SELECT Id
      FROM InspectionResult__c
      WHERE Inspection__c = :targetId AND IsDeficient__c = TRUE
    ];

    Test.startTest();
    List<InspectionResult__c> results = CorrectiveActionController.getDeficientResults(
      targetId
    );
    List<InspectionResult__c> nullResults = CorrectiveActionController.getDeficientResults(
      null
    );
    Test.stopTest();

    Assert.areEqual(1, results.size(), '미흡 항목 1건만 와야 한다');
    Assert.areEqual(
      deficient.Id,
      results[0].Id,
      '만점 항목이 아니라 미흡 항목이어야 한다'
    );
    Assert.isTrue(
      nullResults.isEmpty(),
      'inspectionId가 null이면 빈 목록이어야 한다'
    );
  }

  // 필수 미흡 항목이 비필수보다 먼저 온다 (BR-03)
  @IsTest
  static void getDeficientResults_requiredFirst() {
    Account franchise = new Account(
      Id = [
        SELECT Franchise__c
        FROM Inspection__c
        WHERE InspectionNo__c = :TARGET_INSPECTION_NO
      ]
      .Franchise__c
    );
    Inspection__c orderInspection = TestDataFactory.createInspections(
      new List<Account>{ franchise },
      1,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      false
    )[0];
    orderInspection.InspectionNo__c = ORDER_INSPECTION_NO;
    insert orderInspection;

    // DESC: 비필수 항목을 먼저 넣는다 — 정렬이 없으면 삽입 순서대로 와서 테스트가 실패해야 한다
    List<InspectionTemplateItem__c> templateItems = [
      SELECT Id, Name, Category__c, MaxScore__c, IsRequired__c
      FROM InspectionTemplateItem__c
      ORDER BY IsRequired__c ASC
    ];
    List<InspectionResult__c> results = TestDataFactory.createResults(
      orderInspection,
      templateItems,
      new List<Decimal>{ 5, 5 },
      false
    );
    // NOTE: Category__c 정렬(선택 목록 정의 순서 위생 → 서비스 → 매뉴얼)만으로도 필수가 먼저 오지 않게
    //       필수 항목을 맨 뒤 분류(매뉴얼), 비필수를 맨 앞 분류(위생)로 바꾼다 → IsRequired__c DESC만 검증된다
    results[0].Category__c = '위생';
    results[1].Category__c = '매뉴얼';
    insert results;

    Test.startTest();
    List<InspectionResult__c> deficientResults = CorrectiveActionController.getDeficientResults(
      orderInspection.Id
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      deficientResults.size(),
      '미흡 항목 2건이 모두 와야 한다'
    );
    Assert.isTrue(
      deficientResults[0].IsRequired__c,
      '필수 미흡 항목이 첫 건이어야 한다 (BR-03)'
    );
    Assert.isFalse(
      deficientResults[1].IsRequired__c,
      '비필수 미흡 항목은 그 뒤여야 한다'
    );
  }

  private static Id getInspectionId(String inspectionNo) {
    return [SELECT Id FROM Inspection__c WHERE InspectionNo__c = :inspectionNo]
    .Id;
  }
}
