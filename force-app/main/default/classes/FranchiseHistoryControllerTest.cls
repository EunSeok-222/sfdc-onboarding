/* ======================================================================================
 * @description : 매장 이력 타임라인 조회(getHistory) — 유형 혼합 정렬 · 12개월 범위 · 가맹점 격리 · 벌크 · SV 권한을 검증하는 테스트 클래스
 * @testTarget  : FranchiseHistoryController
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 (테스트 8건)
 *  2026.10.19   Kai        Updated     insertActions를 결과 항목 count개 × 시정조치 1건으로 변경 — 진행 중 시정조치 중복 차단 반영
 * ======================================================================================
 *  @note        : @TestSetup을 쓰지 않는다 — TestDataFactory 점검번호(TEST-0000…)는 트랜잭션마다 0부터 다시 시작해
 *                 공용 데이터와 메서드 안 데이터가 Unique에서 충돌한다. 각 테스트가 필요한 데이터만 만든다
 * ======================================================================================*/
@IsTest
private class FranchiseHistoryControllerTest {
  private static final String STATUS_REQUESTED = '요청';
  private static final String PENALTY_WARNING = '경고';
  private static final String PENALTY_PENDING = '승인대기';

  // 증명: 점검 · 시정조치 · 페널티가 한 목록에 섞여 기준일 내림차순으로 온다
  @IsTest
  static void getHistory_mixedTypes_sortedByDateDesc() {
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    Inspection__c ins = insertInspection(franchise, daysAgo(30), null);
    CorrectiveAction__c action = insertActions(ins, 1)[0];
    Test.setCreatedDate(action.Id, at(daysAgo(20), 10));
    Penalty__c penalty = newPenalty(
      franchise,
      LogisticsNotifyService.PENALTY_TYPE_SUPPLY_RESTRICTION,
      LogisticsNotifyService.PENALTY_STATUS_APPROVED,
      daysAgo(10)
    );
    insert penalty;

    Test.startTest();
    List<FranchiseHistoryController.HistoryEventWrapper> events = FranchiseHistoryController.getHistory(
      franchise.Id
    );
    Test.stopTest();

    Assert.areEqual(3, events.size(), '세 유형이 1건씩 와야 한다');
    Assert.areEqual(
      FranchiseHistoryController.TYPE_PENALTY,
      events[0].eventType,
      '가장 최근(10일 전) 페널티가 첫 건'
    );
    Assert.areEqual(
      FranchiseHistoryController.TYPE_ACTION,
      events[1].eventType,
      '20일 전 시정조치가 두 번째'
    );
    Assert.areEqual(
      FranchiseHistoryController.TYPE_INSPECTION,
      events[2].eventType,
      '30일 전 점검이 마지막'
    );
    Assert.areEqual(
      daysAgo(20),
      events[1].eventDate,
      '시정조치 기준일은 요청일(생성일)'
    );
    Assert.isNotNull(
      events[2].passRate,
      '점검에는 마커 위치용 합격선이 함께 와야 한다'
    );
  }

  // 증명: 같은 날짜면 늦게 생성된 것이 위로 온다
  @IsTest
  static void getHistory_sameDate_sortedByCreatedDesc() {
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    Inspection__c ins = insertInspection(franchise, daysAgo(40), null);
    List<CorrectiveAction__c> actions = insertActions(ins, 2);
    Test.setCreatedDate(actions[0].Id, at(daysAgo(3), 9));
    Test.setCreatedDate(actions[1].Id, at(daysAgo(3), 15));

    Test.startTest();
    List<FranchiseHistoryController.HistoryEventWrapper> events = onlyType(
      FranchiseHistoryController.getHistory(franchise.Id),
      FranchiseHistoryController.TYPE_ACTION
    );
    Test.stopTest();

    Assert.areEqual(2, events.size(), '같은 날 시정조치 2건');
    Assert.areEqual(
      actions[1].Id,
      events[0].recordId,
      '같은 날이면 15시에 생성된 조치가 9시 조치보다 위'
    );
    Assert.areEqual(actions[0].Id, events[1].recordId, '9시 조치가 아래');
  }

  // 증명: 12개월보다 오래된 점검 · 시정조치는 빠지고, 정확히 12개월 전 점검은 포함된다(경계값)
  @IsTest
  static void getHistory_olderThan12Months_excluded() {
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    Date sinceDate = Date.today()
      .addMonths(-FranchiseHistoryController.LOOKBACK_MONTHS);
    Inspection__c oldIns = insertInspection(
      franchise,
      sinceDate.addDays(-1),
      null
    );
    CorrectiveAction__c oldAction = insertActions(oldIns, 1)[0];
    Test.setCreatedDate(oldAction.Id, at(sinceDate.addDays(-1), 10));
    Inspection__c boundaryIns = insertInspection(franchise, sinceDate, null);
    Inspection__c recentIns = insertInspection(franchise, daysAgo(1), null);
    CorrectiveAction__c recentAction = insertActions(recentIns, 1)[0];

    Test.startTest();
    Set<Id> recordIds = recordIdsOf(
      FranchiseHistoryController.getHistory(franchise.Id)
    );
    Test.stopTest();

    Assert.isFalse(
      recordIds.contains(oldIns.Id),
      '12개월 넘은 점검은 빠져야 한다'
    );
    Assert.isFalse(
      recordIds.contains(oldAction.Id),
      '12개월 넘게 전에 요청된 시정조치는 빠져야 한다'
    );
    Assert.isTrue(
      recordIds.contains(boundaryIns.Id),
      '정확히 12개월 전 점검은 포함(>=)되어야 한다'
    );
    Assert.isTrue(recordIds.contains(recentIns.Id), '최근 점검은 와야 한다');
    Assert.isTrue(
      recordIds.contains(recentAction.Id),
      '최근 시정조치는 와야 한다'
    );
    Assert.areEqual(
      3,
      recordIds.size(),
      '경계 점검 · 최근 점검 · 최근 조치 3건만'
    );
  }

  // 증명: 시작일이 없는 페널티(승인 대기)는 생성일 날짜로 들어가고, 생성일이 12개월 넘었으면 빠진다
  @IsTest
  static void getHistory_penaltyWithoutStartDate_usesCreatedDate() {
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    Penalty__c pending = newPenalty(
      franchise,
      PENALTY_WARNING,
      PENALTY_PENDING,
      null
    );
    Penalty__c oldPending = newPenalty(
      franchise,
      PENALTY_WARNING,
      PENALTY_PENDING,
      null
    );
    insert new List<Penalty__c>{ pending, oldPending };
    Test.setCreatedDate(pending.Id, at(daysAgo(5), 11));
    Test.setCreatedDate(oldPending.Id, at(Date.today().addMonths(-13), 11));

    Test.startTest();
    List<FranchiseHistoryController.HistoryEventWrapper> events = FranchiseHistoryController.getHistory(
      franchise.Id
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      events.size(),
      '생성일이 12개월 안인 페널티 1건만 와야 한다'
    );
    Assert.areEqual(pending.Id, events[0].recordId, '최근 승인 대기 페널티');
    Assert.areEqual(
      daysAgo(5),
      events[0].eventDate,
      '시작일이 없으면 생성일 날짜가 기준일이어야 한다'
    );
    Assert.areEqual(PENALTY_WARNING, events[0].penaltyType, '유형이 와야 한다');
  }

  // 증명: 다른 가맹점의 점검 · 시정조치 · 페널티는 섞이지 않는다
  @IsTest
  static void getHistory_otherFranchise_excluded() {
    List<Account> franchises = TestDataFactory.createFranchises(2, true);
    Account target = franchises[0];
    // DESC: 두 가맹점에 점검 · 시정조치 · 페널티를 1건씩. 유형별로 한 번에 insert한다(루프 안 DML 없음)
    List<Inspection__c> inspections = TestDataFactory.createInspections(
      franchises,
      1,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      daysAgo(7),
      true
    );
    List<InspectionTemplateItem__c> items = TestDataFactory.createTemplateItems(
      1,
      1,
      10,
      true
    );
    List<InspectionResult__c> results = new List<InspectionResult__c>();
    for (Inspection__c ins : inspections) {
      results.addAll(
        TestDataFactory.createResults(ins, items, new List<Decimal>{ 5 }, false)
      );
    }
    insert results;
    List<CorrectiveAction__c> actions = TestDataFactory.createCorrectiveActions(
      results,
      1,
      STATUS_REQUESTED,
      Date.today().addDays(3),
      true
    );
    List<Penalty__c> penalties = TestDataFactory.createSupplyRestrictionPenalties(
      franchises,
      true
    );

    // DESC: createInspections · createResults · createCorrectiveActions · createSupplyRestrictionPenalties 모두 가맹점 순서대로 만든다 → 인덱스 0이 대상 가맹점
    Set<Id> targetIds = new Set<Id>{
      inspections[0].Id,
      actions[0].Id,
      penalties[0].Id
    };
    Set<Id> otherIds = new Set<Id>{
      inspections[1].Id,
      actions[1].Id,
      penalties[1].Id
    };

    Test.startTest();
    Set<Id> recordIds = recordIdsOf(
      FranchiseHistoryController.getHistory(target.Id)
    );
    Test.stopTest();

    Assert.areEqual(targetIds, recordIds, '대상 가맹점의 3건만 와야 한다');
    for (Id otherId : otherIds) {
      Assert.isFalse(
        recordIds.contains(otherId),
        '다른 가맹점 레코드가 섞이면 안 된다'
      );
    }
  }

  // 증명: franchiseId가 null이면 SOQL 없이 빈 목록
  @IsTest
  static void getHistory_nullId_returnsEmpty() {
    Test.startTest();
    List<FranchiseHistoryController.HistoryEventWrapper> events = FranchiseHistoryController.getHistory(
      null
    );
    Integer queriesUsed = Limits.getQueries();
    Test.stopTest();

    Assert.isNotNull(events, 'null이 아니라 빈 목록이어야 한다');
    Assert.isTrue(events.isEmpty(), 'franchiseId가 null이면 0건');
    Assert.areEqual(0, queriesUsed, 'null이면 SOQL을 실행하지 않아야 한다');
  }

  // 증명: 점검 · 결과 항목 · 시정조치 각 200건이어도 SOQL은 유형별 1번씩 정확히 3번
  @IsTest
  static void getHistory_bulk200_usesThreeQueries() {
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    List<InspectionTemplateItem__c> items = TestDataFactory.createTemplateItems(
      1,
      1,
      10,
      true
    );
    List<Inspection__c> inspections = TestDataFactory.createInspections(
      new List<Account>{ franchise },
      200,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      daysAgo(1),
      true
    );
    List<InspectionResult__c> results = new List<InspectionResult__c>();
    for (Inspection__c ins : inspections) {
      results.addAll(
        TestDataFactory.createResults(ins, items, new List<Decimal>{ 5 }, false)
      );
    }
    insert results; // DML 1번 — 루프 밖
    TestDataFactory.createCorrectiveActions(
      results,
      1,
      STATUS_REQUESTED,
      null,
      true
    );

    Test.startTest();
    List<FranchiseHistoryController.HistoryEventWrapper> events = FranchiseHistoryController.getHistory(
      franchise.Id
    );
    Integer queriesUsed = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(400, events.size(), '점검 200 + 시정조치 200');
    Assert.areEqual(3, queriesUsed, '건수와 무관하게 SOQL은 유형별 1번씩 3번');
  }

  // 증명: SV에게는 자기 소유 점검과 그 시정조치만 보인다 — 타 SV 소유 점검 · 관리자 소유 페널티는 안 보인다 (BR-10)
  @IsTest
  static void getHistory_runAsSv_hidesOtherSvInspections() {
    User sv = TestDataFactory.createSvUser('이력테스트SV', false);
    User otherSv = TestDataFactory.createSvUser('이력테스트타SV', false);
    insert new List<User>{ sv, otherSv };
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    Inspection__c ownIns = insertInspection(franchise, daysAgo(10), sv.Id);
    CorrectiveAction__c ownAction = insertActions(ownIns, 1)[0];
    Inspection__c otherIns = insertInspection(
      franchise,
      daysAgo(9),
      otherSv.Id
    );
    insertActions(otherIns, 1);
    insert newPenalty(franchise, PENALTY_WARNING, PENALTY_PENDING, daysAgo(8));

    Set<Id> recordIds;
    Test.startTest();
    System.runAs(sv) {
      recordIds = recordIdsOf(
        FranchiseHistoryController.getHistory(franchise.Id)
      );
    }
    Test.stopTest();

    Assert.areEqual(
      new Set<Id>{ ownIns.Id, ownAction.Id },
      recordIds,
      'SV에게는 자기 소유 점검과 그 시정조치만 보여야 한다'
    );
  }

  // ---------------------------------------------------------------- 테스트 데이터 도우미

  private static Date daysAgo(Integer days) {
    return Date.today().addDays(-days);
  }

  private static Datetime at(Date day, Integer hour) {
    return Datetime.newInstance(day, Time.newInstance(hour, 0, 0, 0));
  }

  /** 점검완료 정기점검 1건. ownerId가 null이면 실행 사용자 소유 */
  private static Inspection__c insertInspection(
    Account franchise,
    Date inspectionDate,
    Id ownerId
  ) {
    Inspection__c ins = TestDataFactory.createInspections(
      new List<Account>{ franchise },
      1,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      inspectionDate,
      false
    )[0];
    if (ownerId != null) {
      ins.OwnerId = ownerId;
    }
    insert ins;
    return ins;
  }

  /** 미흡(필수) 결과 항목 count건에 시정조치 1건씩 — 같은 항목에는 진행 중 시정조치를 1건만 둘 수 있다(중복 차단) */
  private static List<CorrectiveAction__c> insertActions(
    Inspection__c ins,
    Integer count
  ) {
    List<Decimal> scores = new List<Decimal>();
    for (Integer i = 0; i < count; i++) {
      scores.add(5);
    }
    List<InspectionResult__c> results = TestDataFactory.createResults(
      ins,
      TestDataFactory.createTemplateItems(count, count, 10, true),
      scores,
      true
    );
    return TestDataFactory.createCorrectiveActions(
      results,
      1,
      STATUS_REQUESTED,
      Date.today().addDays(3),
      true
    );
  }

  /** 기존 Factory의 공급 제한 페널티를 받아 유형 · 상태 · 기간만 바꾼다 (insert 전) */
  private static Penalty__c newPenalty(
    Account franchise,
    String penaltyType,
    String status,
    Date startDate
  ) {
    Penalty__c penalty = TestDataFactory.createSupplyRestrictionPenalties(
      new List<Account>{ franchise },
      false
    )[0];
    penalty.PenaltyType__c = penaltyType;
    penalty.Status__c = status;
    penalty.StartDate__c = startDate;
    penalty.EndDate__c = startDate == null ? null : startDate.addDays(6);
    return penalty;
  }

  private static Set<Id> recordIdsOf(
    List<FranchiseHistoryController.HistoryEventWrapper> events
  ) {
    Set<Id> ids = new Set<Id>();
    for (FranchiseHistoryController.HistoryEventWrapper event : events) {
      ids.add(event.recordId);
    }
    return ids;
  }

  private static List<FranchiseHistoryController.HistoryEventWrapper> onlyType(
    List<FranchiseHistoryController.HistoryEventWrapper> events,
    String eventType
  ) {
    List<FranchiseHistoryController.HistoryEventWrapper> filtered = new List<FranchiseHistoryController.HistoryEventWrapper>();
    for (FranchiseHistoryController.HistoryEventWrapper event : events) {
      if (event.eventType == eventType) {
        filtered.add(event);
      }
    }
    return filtered;
  }
}
