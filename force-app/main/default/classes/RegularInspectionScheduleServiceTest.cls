/* ======================================================================================
 * @description : 다음 정기점검 자동 생성(BR-01) — 점검일 규칙 · 대상 선별 · 소유자 · 배치 · 스케줄러를 검증한다
 * @testTarget  : RegularInspectionScheduleService, RegularInspectionBatch, RegularInspectionScheduler
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — 점검일 5규칙, 생성 · 건너뜀(진행 중 · 비활성 · 매장코드 없음), 비활성 소유자 큐, 벌크 200, 배치 · 스케줄러
 * ======================================================================================*/
@IsTest
private class RegularInspectionScheduleServiceTest {
  private static final Integer TEMPLATE_COUNT = 20;
  private static final Integer BULK_SIZE = 200;

  @TestSetup
  static void setupData() {
    // NOTE: 점검 트리거가 활성 점검표 항목으로 결과 항목을 만든다 — 20항목
    TestDataFactory.createTemplateItems(TEMPLATE_COUNT, 6, 5, true);
  }

  // ---------------------------------------------------------------- 점검일 규칙

  // 증명: 월 1회 · 신규 매장 15일 · 기준일 없음 · 계산일이 과거면 오늘
  @IsTest
  static void nextInspectionDate_followsBr01Rules() {
    Date today = Date.newInstance(2026, 10, 19);

    Assert.areEqual(
      Date.newInstance(2026, 10, 24),
      RegularInspectionScheduleService.nextInspectionDate(
        Date.newInstance(2026, 9, 24),
        Date.newInstance(2020, 1, 1),
        today
      ),
      '기존 매장 = 최근 점검일 + 1개월'
    );
    Assert.areEqual(
      Date.newInstance(2026, 10, 25),
      RegularInspectionScheduleService.nextInspectionDate(
        Date.newInstance(2026, 10, 10),
        Date.newInstance(2026, 8, 1),
        today
      ),
      '오픈 3개월 이내 = 최근 점검일 + 15일'
    );
    Assert.areEqual(
      today,
      RegularInspectionScheduleService.nextInspectionDate(
        null,
        Date.newInstance(2026, 9, 1),
        today
      ),
      '최근 점검일이 없으면 오픈일 기준(9/16) — 오늘보다 이르면 오늘'
    );
    Assert.areEqual(
      Date.newInstance(2026, 11, 3),
      RegularInspectionScheduleService.nextInspectionDate(
        null,
        Date.newInstance(2026, 10, 19),
        today
      ),
      '오늘 오픈한 매장 = 오픈일 + 15일'
    );
    Assert.areEqual(
      today,
      RegularInspectionScheduleService.nextInspectionDate(null, null, today),
      '기준일이 없으면 오늘'
    );
  }

  // ---------------------------------------------------------------- 생성 · 건너뜀

  // 증명: 활성 가맹점에 점검예정 정기점검 1건 — 소유자 = 가맹점 소유자, 결과 항목 20행(점검 트리거)
  @IsTest
  static void createNext_scheduledRegularWithResults() {
    Account franchise = TestDataFactory.createFranchises(1, true)[0];

    Test.startTest();
    List<Inspection__c> created = RegularInspectionScheduleService.createNextInspections(
      queryFranchises(new Set<Id>{ franchise.Id })
    );
    Test.stopTest();

    Assert.areEqual(1, created.size(), '1건 생성');
    Inspection__c saved = [
      SELECT
        Status__c,
        RecordType.DeveloperName,
        InspectionDate__c,
        OwnerId,
        InspectionNo__c,
        (SELECT Id FROM InspectionInspectionResults__r)
      FROM Inspection__c
      WHERE Id = :created[0].Id
    ];
    Assert.areEqual('점검예정', saved.Status__c, '점검예정');
    Assert.areEqual('Regular', saved.RecordType.DeveloperName, '정기점검');
    Assert.areEqual(
      Date.today(),
      saved.InspectionDate__c,
      '기준일이 없으면 오늘'
    );
    Assert.areEqual(UserInfo.getUserId(), saved.OwnerId, '가맹점 소유자');
    Assert.isNull(
      saved.InspectionNo__c,
      '이관번호 없음 — 결과 항목 자동 생성 대상'
    );
    Assert.areEqual(
      TEMPLATE_COUNT,
      saved.InspectionInspectionResults__r.size(),
      '결과 항목 20행'
    );
  }

  // 증명: 점검예정 정기점검이 있는 가맹점 · Active__c = No · 매장코드 없는 계정은 만들지 않는다. 다시 돌려도 중복 없음
  @IsTest
  static void createNext_skipsScheduledInactiveAndNonFranchise() {
    List<Account> accounts = TestDataFactory.createFranchises(4, false);
    accounts[1].Active__c = 'No';
    accounts[2].StoreCode__c = null;
    insert accounts;
    TestDataFactory.createInspections(
      new List<Account>{ accounts[3] },
      1,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today().addDays(3),
      true
    );
    Set<Id> accountIds = new Map<Id, Account>(accounts).keySet();

    Test.startTest();
    List<Inspection__c> first = RegularInspectionScheduleService.createNextInspections(
      queryFranchises(accountIds)
    );
    List<Inspection__c> second = RegularInspectionScheduleService.createNextInspections(
      queryFranchises(accountIds)
    );
    Test.stopTest();

    Assert.areEqual(1, first.size(), '활성 · 점검예정 없음인 가맹점 1곳만');
    Assert.areEqual(accounts[0].Id, first[0].Franchise__c, '첫 가맹점');
    Assert.areEqual(0, second.size(), '다시 돌리면 이미 점검예정이 있어 0건');
  }

  // 증명: 가맹점 소유자가 비활성이면 미배정 점검 큐에 배정한다
  @IsTest
  static void createNext_inactiveOwner_assignedToUnassignedQueue() {
    User leaver = TestDataFactory.createSvUser('정기점검퇴사SV', true);
    Account franchise = TestDataFactory.createFranchises(1, false)[0];
    franchise.OwnerId = leaver.Id;
    insert franchise;
    // NOTE: 사용자(설정 개체) 변경은 업무 데이터 DML과 다른 runAs 블록에서 — Mixed DML 회피
    System.runAs(new User(Id = UserInfo.getUserId())) {
      update new User(Id = leaver.Id, IsActive = false);
    }

    Test.startTest();
    List<Inspection__c> created = RegularInspectionScheduleService.createNextInspections(
      queryFranchises(new Set<Id>{ franchise.Id })
    );
    Test.stopTest();

    Id queueId = [
      SELECT Id
      FROM Group
      WHERE Type = 'Queue' AND DeveloperName = 'UnassignedInspection'
    ]
    .Id;
    Assert.areEqual(
      queueId,
      [SELECT OwnerId FROM Inspection__c WHERE Id = :created[0].Id].OwnerId,
      '비활성 소유자 → 미배정 점검 큐'
    );
  }

  // 증명: 200곳을 한 번에 넘겨도 점검 insert 1번 · 쿼리 수가 건수에 비례하지 않는다
  @IsTest
  static void createNext_bulk200_oneInsertConstantQueries() {
    List<Account> franchises = TestDataFactory.createFranchises(
      BULK_SIZE,
      true
    );
    List<Account> scope = queryFranchises(
      new Map<Id, Account>(franchises).keySet()
    );

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    Integer dmlBefore = Limits.getDmlStatements();
    List<Inspection__c> created = RegularInspectionScheduleService.createNextInspections(
      scope
    );
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
    Test.stopTest();

    Assert.areEqual(BULK_SIZE, created.size(), '200곳 모두 생성');
    // NOTE: 점검예정 확인 1 + 점검 트리거(점검표 조회) — 결과 항목 insert는 트리거 안에서 1번
    Assert.isTrue(
      queriesUsed <= 3,
      '쿼리 수가 건수와 무관해야 한다. 실제: ' + queriesUsed
    );
    Assert.isTrue(
      dmlUsed <= 2,
      '점검 insert 1 + 결과 항목 insert 1. 실제: ' + dmlUsed
    );
  }

  // ---------------------------------------------------------------- 배치 · 스케줄러

  // 증명: 가맹점 Id를 지정하면 그 가맹점만 처리한다(스모크 1곳)
  @IsTest
  static void batch_withFranchiseIds_processesOnlyThose() {
    List<Account> franchises = TestDataFactory.createFranchises(2, true);

    Test.startTest();
    Database.executeBatch(
      new RegularInspectionBatch(new Set<Id>{ franchises[0].Id }),
      RegularInspectionBatch.BATCH_SIZE
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Inspection__c
        WHERE Franchise__c = :franchises[0].Id
      ],
      '지정한 가맹점은 1건'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Inspection__c
        WHERE Franchise__c = :franchises[1].Id
      ],
      '지정하지 않은 가맹점은 0건'
    );
  }

  // 증명: 스케줄러가 전체 대상 배치를 돌린다
  @IsTest
  static void scheduler_execute_runsBatchForAllActive() {
    List<Account> franchises = TestDataFactory.createFranchises(3, true);

    Test.startTest();
    new RegularInspectionScheduler().execute(null);
    Test.stopTest();

    Assert.areEqual(
      3,
      [SELECT COUNT() FROM Inspection__c WHERE Franchise__c IN :franchises],
      '활성 가맹점 3곳 모두'
    );
  }

  // ---------------------------------------------------------------- 도우미

  private static List<Account> queryFranchises(Set<Id> accountIds) {
    return [
      SELECT
        Id,
        OwnerId,
        Owner.IsActive,
        OpenDate__c,
        LastRegularInspectionDate__c,
        StoreCode__c,
        Active__c
      FROM Account
      WHERE Id IN :accountIds
      ORDER BY Name
    ];
  }
}
