/* ======================================================================================
 * @description : 내 점검 목록 검색 · 정렬 · 페이징을 검증하는 테스트 클래스
 * @testTarget  : InspectionListController
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.13   Kai        Created     최초 작성
 *  2026.10.13   Kai        Updated     statuses(List) 변경 반영 — 상태 2개 · 빈 목록 케이스 추가
 *  2026.10.14   Kai        Updated     SV 권한(runAs) 레코드 층 테스트 추가 (BR-10 담당 점검만)
 * ======================================================================================*/
@IsTest
private class InspectionListControllerTest {
  private static final String STATUS_CORRECTING = '시정중';
  private static final String STATUS_DELAYED = '지연';

  // 가맹점명 키워드 + 상태 조건이 함께 걸리고, 다른 가맹점 · 다른 상태는 빠진다
  @IsTest
  static void search_keywordAndStatus_returnsMatchingOnly() {
    // NOTE: 가맹점 이름은 TEST가맹점-0000, TEST가맹점-0001
    List<Account> franchises = TestDataFactory.createFranchises(2, true);
    Account target = franchises[1];
    TestDataFactory.createInspections(
      new List<Account>{ franchises[0] },
      3,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    );
    TestDataFactory.createInspections(
      new List<Account>{ target },
      2,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    );
    TestDataFactory.createInspections(
      new List<Account>{ target },
      1,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    );

    InspectionListController.SearchCriteria criteria = new InspectionListController.SearchCriteria();
    criteria.keyword = '0001';
    criteria.statuses = new List<String>{ TestDataFactory.STATUS_SCHEDULED };

    Test.startTest();
    InspectionListController.InspectionPageWrapper page = InspectionListController.search(
      criteria
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      page.totalCount,
      '키워드 · 상태가 모두 맞는 점검은 2건이어야 한다'
    );
    Assert.areEqual(2, page.records.size(), '1페이지에 2건이 모두 나와야 한다');
    for (Inspection__c ins : page.records) {
      Assert.areEqual(
        target.Id,
        ins.Franchise__c,
        '다른 가맹점 점검이 섞이면 안 된다'
      );
      Assert.areEqual(
        TestDataFactory.STATUS_SCHEDULED,
        ins.Status__c,
        '다른 상태 점검이 섞이면 안 된다'
      );
    }
  }

  // 「시정 대기」 칩처럼 상태 2개를 넘기면 두 상태가 모두 나오고 다른 상태는 빠진다
  @IsTest
  static void search_twoStatuses_returnsBoth() {
    createInspectionsByStatus();

    InspectionListController.SearchCriteria criteria = new InspectionListController.SearchCriteria();
    criteria.statuses = new List<String>{ STATUS_CORRECTING, STATUS_DELAYED };

    Test.startTest();
    InspectionListController.InspectionPageWrapper page = InspectionListController.search(
      criteria
    );
    Test.stopTest();

    Assert.areEqual(
      3,
      page.totalCount,
      '시정중 2건 + 지연 1건 = 3건이어야 한다'
    );
    Set<String> foundStatuses = new Set<String>();
    for (Inspection__c ins : page.records) {
      foundStatuses.add(ins.Status__c);
    }
    Assert.areEqual(
      new Set<String>{ STATUS_CORRECTING, STATUS_DELAYED },
      foundStatuses,
      '시정중과 지연이 모두 나오고 점검예정은 빠져야 한다'
    );
  }

  // 「전체」 칩은 빈 목록을 넘긴다 — 상태 조건 없이 모든 상태가 나온다
  @IsTest
  static void search_emptyStatuses_returnsAll() {
    createInspectionsByStatus();

    InspectionListController.SearchCriteria criteria = new InspectionListController.SearchCriteria();
    criteria.statuses = new List<String>();

    Test.startTest();
    InspectionListController.InspectionPageWrapper page = InspectionListController.search(
      criteria
    );
    Test.stopTest();

    Assert.areEqual(
      6,
      page.totalCount,
      '빈 목록이면 상태와 상관없이 6건 모두 나와야 한다'
    );
  }

  // 25건 · 페이지당 20건이면 2페이지는 21번째부터 5건이고, 전체 건수는 25건 그대로다
  @IsTest
  static void search_secondPage_startsAtTwentyFirst() {
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    List<Inspection__c> inspections = TestDataFactory.createInspections(
      new List<Account>{ franchise },
      25,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      null,
      false
    );
    // DESC: 점검일을 하루씩 다르게 — 기본 정렬(점검일 ASC)에서 i번째 = 오늘 + i일
    for (Integer i = 0; i < inspections.size(); i++) {
      inspections[i].InspectionDate__c = Date.today().addDays(i);
    }
    insert inspections;

    InspectionListController.SearchCriteria criteria = new InspectionListController.SearchCriteria();
    criteria.pageSize = 20;
    criteria.pageNumber = 2;

    Test.startTest();
    InspectionListController.InspectionPageWrapper page = InspectionListController.search(
      criteria
    );
    Test.stopTest();

    Assert.areEqual(
      25,
      page.totalCount,
      '전체 건수는 페이지와 상관없이 25건이어야 한다'
    );
    Assert.areEqual(5, page.records.size(), '2페이지는 나머지 5건이어야 한다');
    Assert.areEqual(
      Date.today().addDays(20),
      page.records[0].InspectionDate__c,
      '2페이지 첫 건은 21번째(오늘 + 20일) 점검이어야 한다'
    );
  }

  // 화이트리스트에 없는 정렬 컬럼은 SOQL을 만들기 전에 거부한다 (ORDER BY 인젝션 방지)
  @IsTest
  static void search_sortByNotInWhitelist_throws() {
    InspectionListController.SearchCriteria criteria = new InspectionListController.SearchCriteria();
    criteria.sortBy = 'Name) FROM User --';

    try {
      InspectionListController.search(criteria);
      Assert.fail('화이트리스트에 없는 정렬 컬럼은 예외가 나야 한다');
    } catch (AuraHandledException e) {
      Assert.isTrue(
        e.getMessage().contains('정렬할 수 없는 컬럼'),
        '정렬 컬럼 거부 메시지여야 한다. 실제: ' + e.getMessage()
      );
    }
  }

  // 정렬 방향도 문자열로 SOQL에 붙으므로 asc / desc 외에는 거부한다
  @IsTest
  static void search_invalidSortDir_throws() {
    InspectionListController.SearchCriteria criteria = new InspectionListController.SearchCriteria();
    criteria.sortDir = 'ASC LIMIT 1';

    try {
      InspectionListController.search(criteria);
      Assert.fail('asc / desc 외의 정렬 방향은 예외가 나야 한다');
    } catch (AuraHandledException e) {
      Assert.isTrue(
        e.getMessage().contains('정렬 방향'),
        '정렬 방향 거부 메시지여야 한다. 실제: ' + e.getMessage()
      );
    }
  }

  // OFFSET 2,000을 넘는 페이지는 SOQL 오류 대신 안내 메시지로 거부한다
  @IsTest
  static void search_offsetOverLimit_throws() {
    InspectionListController.SearchCriteria criteria = new InspectionListController.SearchCriteria();
    criteria.pageSize = 20;
    criteria.pageNumber = 102; // offset 2,020

    try {
      InspectionListController.search(criteria);
      Assert.fail('OFFSET 2,000 초과는 예외가 나야 한다');
    } catch (AuraHandledException e) {
      Assert.isTrue(
        e.getMessage().contains('범위를 넘었습니다'),
        'OFFSET 초과 안내 메시지여야 한다. 실제: ' + e.getMessage()
      );
    }
  }

  // 200건이어도 SOQL은 목록 1번 + 건수 1번이고, 조건이 없으면 기본 20건 · 내림차순도 동작한다
  @IsTest
  static void search_bulk200_usesTwoQueries() {
    List<Account> franchises = TestDataFactory.createFranchises(4, true);
    List<Inspection__c> inspections = TestDataFactory.createInspections(
      franchises,
      50,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      null,
      false
    );
    for (Integer i = 0; i < inspections.size(); i++) {
      inspections[i].InspectionDate__c = Date.today().addDays(i);
    }
    insert inspections;

    InspectionListController.SearchCriteria criteria = new InspectionListController.SearchCriteria();
    criteria.sortDir = 'desc';

    Test.startTest();
    InspectionListController.InspectionPageWrapper page = InspectionListController.search(
      criteria
    );
    Integer queriesUsed = Limits.getQueries();
    InspectionListController.InspectionPageWrapper defaultPage = InspectionListController.search(
      null
    );
    Test.stopTest();

    Assert.areEqual(200, page.totalCount, '전체 건수는 200건이어야 한다');
    Assert.areEqual(
      20,
      page.records.size(),
      'pageSize를 비우면 기본 20건이어야 한다'
    );
    Assert.areEqual(
      Date.today().addDays(199),
      page.records[0].InspectionDate__c,
      'desc면 가장 늦은 점검일이 첫 건이어야 한다'
    );
    Assert.areEqual(2, queriesUsed, 'SOQL은 목록 1번 + 건수 1번이어야 한다');
    Assert.areEqual(
      Date.today(),
      defaultPage.records[0].InspectionDate__c,
      'criteria가 null이면 기본 정렬(점검일 ASC)이어야 한다'
    );
  }

  // DESC: 가맹점 1곳에 점검예정 3 · 시정중 2 · 지연 1 (DML: 가맹점 1번 + 점검 1번)
  private static void createInspectionsByStatus() {
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    List<Account> franchises = new List<Account>{ franchise };
    List<Inspection__c> inspections = new List<Inspection__c>();
    inspections.addAll(
      TestDataFactory.createInspections(
        franchises,
        3,
        TestDataFactory.STATUS_SCHEDULED,
        TestDataFactory.RT_REGULAR,
        Date.today(),
        false
      )
    );
    inspections.addAll(
      TestDataFactory.createInspections(
        franchises,
        2,
        STATUS_CORRECTING,
        TestDataFactory.RT_REGULAR,
        Date.today(),
        false
      )
    );
    inspections.addAll(
      TestDataFactory.createInspections(
        franchises,
        1,
        STATUS_DELAYED,
        TestDataFactory.RT_REGULAR,
        Date.today(),
        false
      )
    );
    insert inspections;
  }

  // ---------------------------------------------------------------- 권한 축소 사용자 (BR-10 레코드 층)

  // 증명: SV가 목록을 열면 with sharing + USER_MODE가 SV 소유 점검만 남긴다.
  //       타 SV · 관리자 소유 점검을 섞어 두고, 건수와 소유자가 정확히 SV 것뿐인지 본다
  // NOTE: @TestSetup을 쓰지 않는다 — 이 클래스의 기존 테스트가 전체 건수(200건 등)를 Assert하므로
  //       공용 데이터를 깔면 그 테스트들이 깨진다. 이 테스트에 필요한 데이터는 여기서만 만든다
  @IsTest
  static void search_asSv_returnsOnlyOwnInspections() {
    User sv = TestDataFactory.createSvUser('목록테스트SV', false);
    User otherSv = TestDataFactory.createSvUser('목록테스트타SV', false);
    insert new List<User>{ sv, otherSv };

    // DESC: 가맹점 3곳 × 2건 = 6건 — SV 2건 · 타 SV 2건 · 관리자(실행 사용자) 2건
    List<Inspection__c> inspections = TestDataFactory.createInspections(
      TestDataFactory.createFranchises(3, true),
      2,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      false
    );
    Integer svOwnedCount = 0;
    for (Integer i = 0; i < inspections.size(); i++) {
      if (i < 2) {
        inspections[i].OwnerId = sv.Id;
        svOwnedCount++;
      } else if (i < 4) {
        inspections[i].OwnerId = otherSv.Id;
      }
    }
    insert inspections;
    Assert.areEqual(
      6,
      [SELECT COUNT() FROM Inspection__c],
      '전제: 소유자가 섞인 점검 6건이 있어야 한다'
    );

    InspectionListController.InspectionPageWrapper page;
    Test.startTest();
    System.runAs(sv) {
      page = InspectionListController.search(null);
    }
    Test.stopTest();

    Assert.areEqual(
      svOwnedCount,
      page.totalCount,
      'SV에게는 자기 소유 점검 건수만 잡혀야 한다'
    );
    Assert.areEqual(
      svOwnedCount,
      page.records.size(),
      'SV에게 반환된 레코드도 자기 소유 건수와 같아야 한다'
    );
    // NOTE: 컨트롤러의 SELECT에는 OwnerId가 없다(화면에 안 쓰는 필드는 가져오지 않는다). 반환된 Id로 소유자를 다시 조회한다
    Set<Id> returnedIds = new Map<Id, Inspection__c>(page.records).keySet();
    for (Inspection__c ins : [
      SELECT OwnerId
      FROM Inspection__c
      WHERE Id IN :returnedIds
    ]) {
      Assert.areEqual(
        sv.Id,
        ins.OwnerId,
        'SV 목록에 타 사용자 소유 점검이 섞이면 안 된다'
      );
    }
  }
}
