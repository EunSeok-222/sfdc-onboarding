/* ======================================================================================
 * @description : PenaltyService(공급 제한 기간 자동 · 진행 중 페널티 중복 차단)와 검증 규칙 PeriodStartBeforeEnd를 검증한다
 * @testTarget  : PenaltyService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — 기간 자동(정상 · 입력값 유지 · 승인 후 미적용 · 벌크 200) · 기간 역전 · 중복(DB · 같은 묶음 · 반려 · 비공개)
 * ======================================================================================*/
@IsTest
private class PenaltyServiceTest {
  private static final Integer BULK_SIZE = 200;
  private static final String TYPE_WARNING = '경고';

  // ---------------------------------------------------------------- 공급 제한 기간 자동

  // 증명: 공급 제한을 기간 없이 만들면 내일부터 기준 일수(Default 7일)만큼 채워진다
  @IsTest
  static void insert_supplyRestrictionWithoutPeriod_startsTomorrowForRuleDays() {
    Inspection__c source = insertSources(1)[0];

    Test.startTest();
    Penalty__c penalty = newPenalty(
      source,
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    insert penalty;
    Test.stopTest();

    Penalty__c saved = getPenalty(penalty.Id);
    Date tomorrow = Date.today().addDays(1);
    Assert.areEqual(tomorrow, saved.StartDate__c, '시작일 = 내일');
    Assert.areEqual(
      tomorrow.addDays(InspectionRuleSelector.getSupplyRestrictionDays() - 1),
      saved.EndDate__c,
      '종료일 = 시작일 + (일수 - 1)'
    );
  }

  // 증명: 사용자가 넣은 값은 덮어쓰지 않는다 — 시작일만 넣으면 종료일만 채우고, 둘 다 넣으면 그대로
  @IsTest
  static void insert_userEnteredDates_areKept() {
    List<Inspection__c> sources = insertSources(2);
    Date start = Date.today().addDays(10);
    Penalty__c startOnly = newPenalty(
      sources[0],
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    startOnly.StartDate__c = start;
    Penalty__c both = newPenalty(
      sources[1],
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    both.StartDate__c = start;
    both.EndDate__c = start.addDays(2);

    Test.startTest();
    insert new List<Penalty__c>{ startOnly, both };
    Test.stopTest();

    Penalty__c savedStartOnly = getPenalty(startOnly.Id);
    Assert.areEqual(start, savedStartOnly.StartDate__c, '입력한 시작일 유지');
    Assert.areEqual(
      start.addDays(InspectionRuleSelector.getSupplyRestrictionDays() - 1),
      savedStartOnly.EndDate__c,
      '종료일은 입력한 시작일 기준으로 채운다'
    );
    Penalty__c savedBoth = getPenalty(both.Id);
    Assert.areEqual(start, savedBoth.StartDate__c, '시작일 유지');
    Assert.areEqual(start.addDays(2), savedBoth.EndDate__c, '종료일 유지');
  }

  // 증명: 경고는 기간을 채우지 않는다
  @IsTest
  static void insert_warning_periodStaysBlank() {
    Inspection__c source = insertSources(1)[0];

    Test.startTest();
    Penalty__c penalty = newPenalty(source, TYPE_WARNING);
    insert penalty;
    Test.stopTest();

    Penalty__c saved = getPenalty(penalty.Id);
    Assert.isNull(saved.StartDate__c, '경고는 시작일을 채우지 않는다');
    Assert.isNull(saved.EndDate__c, '경고는 종료일을 채우지 않는다');
  }

  // 증명: update는 승인대기에서만 채운다 — 승인대기 경고를 공급 제한으로 바꾸면 채우고, 승인된 건은 비워도 다시 채우지 않는다
  @IsTest
  static void update_fillsOnlyWhilePending() {
    List<Inspection__c> sources = insertSources(2);
    Penalty__c pending = newPenalty(sources[0], TYPE_WARNING);
    Penalty__c approved = newPenalty(
      sources[1],
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    approved.Status__c = PenaltyService.STATUS_APPROVED;
    insert new List<Penalty__c>{ pending, approved };

    Test.startTest();
    pending.PenaltyType__c = PenaltyService.TYPE_SUPPLY_RESTRICTION;
    approved.StartDate__c = null;
    approved.EndDate__c = null;
    update new List<Penalty__c>{ pending, approved };
    Test.stopTest();

    Assert.areEqual(
      Date.today().addDays(1),
      getPenalty(pending.Id).StartDate__c,
      '승인대기 상태에서 공급 제한이 되면 기간을 채운다'
    );
    Penalty__c savedApproved = getPenalty(approved.Id);
    Assert.isNull(savedApproved.StartDate__c, '승인 뒤에는 채우지 않는다');
    Assert.isNull(savedApproved.EndDate__c, '승인 뒤에는 채우지 않는다');
  }

  // 증명: 시작일 > 종료일은 검증 규칙이 막는다(물류 org 400 방지)
  @IsTest
  static void insert_startAfterEnd_blockedByValidationRule() {
    Inspection__c source = insertSources(1)[0];
    Penalty__c penalty = newPenalty(
      source,
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    penalty.StartDate__c = Date.today().addDays(2);
    penalty.EndDate__c = Date.today().addDays(1);

    Test.startTest();
    Database.SaveResult result = Database.insert(penalty, false);
    Test.stopTest();

    Assert.isFalse(result.isSuccess(), '기간 역전은 저장되면 안 된다');
    Assert.areEqual(
      '종료일은 시작일과 같거나 그 뒤여야 합니다.',
      result.getErrors()[0].getMessage(),
      '검증 규칙 문구'
    );
  }

  // 증명: 200건을 한 번에 넣어도 모두 기간이 채워지고, 중복 검사 SOQL은 1번이다
  @IsTest
  static void bulk200_periodsFilledAndOneDuplicateQuery() {
    List<Inspection__c> sources = insertSources(BULK_SIZE);
    List<Penalty__c> penalties = new List<Penalty__c>();
    for (Inspection__c source : sources) {
      penalties.add(newPenalty(source, PenaltyService.TYPE_SUPPLY_RESTRICTION));
    }

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    insert penalties;
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    Assert.areEqual(
      BULK_SIZE,
      [
        SELECT COUNT()
        FROM Penalty__c
        WHERE Id IN :penalties AND StartDate__c != NULL AND EndDate__c != NULL
      ],
      '200건 모두 기간이 채워져야 한다'
    );
    // NOTE: 중복 검사 1번만 — 기준값(Custom Metadata getInstance)은 SOQL 한도를 쓰지 않는다
    Assert.areEqual(
      1,
      queriesUsed,
      '200건이어도 SOQL 1번이어야 한다. 실제: ' + queriesUsed
    );
  }

  // ---------------------------------------------------------------- 중복 차단

  // 증명: 같은 근거 점검 · 같은 유형으로 진행 중인 페널티가 있으면 막고, 기존 번호를 알려 준다
  @IsTest
  static void duplicate_sameSourceAndType_blockedWithExistingNo() {
    Inspection__c source = insertSources(1)[0];
    Penalty__c existing = newPenalty(
      source,
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    insert existing;
    String existingNo = getPenalty(existing.Id).Name;

    Test.startTest();
    Database.SaveResult result = Database.insert(
      newPenalty(source, PenaltyService.TYPE_SUPPLY_RESTRICTION),
      false
    );
    Test.stopTest();

    Assert.isFalse(
      result.isSuccess(),
      '진행 중인 같은 페널티가 있으면 막아야 한다'
    );
    Assert.areEqual(
      '이 점검을 근거로 진행 중인 공급 제한 페널티가 있습니다: ' + existingNo,
      result.getErrors()[0].getMessage(),
      '기존 페널티 번호를 알려 줘야 한다'
    );
  }

  // 증명: 같은 저장 묶음 안의 중복도 막는다 — 첫 행은 저장, 두 번째부터 거부
  @IsTest
  static void duplicate_sameBatch_secondRowBlocked() {
    Inspection__c source = insertSources(1)[0];

    Test.startTest();
    List<Database.SaveResult> results = Database.insert(
      new List<Penalty__c>{
        newPenalty(source, PenaltyService.TYPE_SUPPLY_RESTRICTION),
        newPenalty(source, PenaltyService.TYPE_SUPPLY_RESTRICTION)
      },
      false
    );
    Test.stopTest();

    Assert.isTrue(results[0].isSuccess(), '첫 행은 저장된다');
    Assert.isFalse(results[1].isSuccess(), '두 번째 행은 막혀야 한다');
    Assert.isTrue(
      results[1].getErrors()[0].getMessage().contains('같이 저장하는 다른 행'),
      '같은 묶음 중복 문구. 실제: ' + results[1].getErrors()[0].getMessage()
    );
  }

  // 증명: 반려된 페널티 · 다른 유형 · 근거 점검 없음은 중복이 아니다
  @IsTest
  static void duplicate_rejectedOrOtherTypeOrNoSource_allowed() {
    Inspection__c source = insertSources(1)[0];
    Penalty__c rejected = newPenalty(
      source,
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    rejected.Status__c = PenaltyService.STATUS_REJECTED;
    Penalty__c warning = newPenalty(source, TYPE_WARNING);
    Penalty__c noSourceA = newPenalty(
      null,
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    noSourceA.Franchise__c = source.Franchise__c;
    insert new List<Penalty__c>{ rejected, warning, noSourceA };

    Test.startTest();
    Penalty__c afterRejected = newPenalty(
      source,
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    Penalty__c noSourceB = newPenalty(
      null,
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    noSourceB.Franchise__c = source.Franchise__c;
    List<Database.SaveResult> results = Database.insert(
      new List<Penalty__c>{ afterRejected, noSourceB },
      false
    );
    Test.stopTest();

    Assert.isTrue(
      results[0].isSuccess(),
      '반려 뒤 재발의 · 다른 유형(경고)이 있어도 저장된다: ' +
      results[0].getErrors()
    );
    Assert.isTrue(
      results[1].isSuccess(),
      '근거 점검이 없으면 검사하지 않는다: ' + results[1].getErrors()
    );
  }

  // 증명: update로 근거 점검을 바꿔 중복이 되면 막는다. 근거 · 유형이 그대로인 재저장은 다시 검사하지 않는다
  @IsTest
  static void update_sourceChangedToDuplicate_blocked() {
    List<Inspection__c> sources = insertSources(2);
    Penalty__c first = newPenalty(
      sources[0],
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    Penalty__c second = newPenalty(
      sources[1],
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    insert new List<Penalty__c>{ first, second };

    Test.startTest();
    Database.SaveResult resave = Database.update(
      new Penalty__c(Id = second.Id, Reason__c = '사유만 수정'),
      false
    );
    Database.SaveResult moved = Database.update(
      new Penalty__c(Id = second.Id, SourceInspection__c = sources[0].Id),
      false
    );
    Test.stopTest();

    Assert.isTrue(
      resave.isSuccess(),
      '근거 · 유형이 그대로면 저장된다: ' + resave.getErrors()
    );
    Assert.isFalse(
      moved.isSuccess(),
      '근거 점검을 바꿔 중복이 되면 막아야 한다'
    );
  }

  // 증명: 저장하는 사용자가 볼 수 없는(OWD 비공개 · 다른 사람 소유) 진행 중 페널티도 중복으로 잡는다
  @IsTest
  static void duplicate_invisibleToSavingUser_stillBlocked() {
    User regionManager = TestDataFactory.createRegionManagerUser(
      '중복검사팀장',
      true
    );
    User otherSv = TestDataFactory.createSvUser('중복검사SV', true);
    Inspection__c source = insertSources(1)[0];
    // NOTE: 권역팀장이 근거 점검 · 가맹점을 조회할 수 있어야 lookup을 저장할 수 있다 — 소유자를 권역팀장으로
    update new Account(Id = source.Franchise__c, OwnerId = regionManager.Id);
    update new Inspection__c(Id = source.Id, OwnerId = regionManager.Id);
    Penalty__c hidden = newPenalty(
      source,
      PenaltyService.TYPE_SUPPLY_RESTRICTION
    );
    hidden.OwnerId = otherSv.Id;
    insert hidden;

    Database.SaveResult result;
    Integer visibleToManager;
    Test.startTest();
    System.runAs(regionManager) {
      visibleToManager = [SELECT COUNT() FROM Penalty__c WHERE Id = :hidden.Id];
      result = Database.insert(
        newPenalty(source, PenaltyService.TYPE_SUPPLY_RESTRICTION),
        false
      );
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      visibleToManager,
      '전제: 권역팀장은 다른 SV 소유 페널티를 볼 수 없다'
    );
    Assert.isFalse(
      result.isSuccess(),
      '보이지 않는 진행 중 페널티도 중복으로 막아야 한다'
    );
  }

  // ---------------------------------------------------------------- 도우미

  /** 근거 점검(점검완료 · 정기) count건 — 가맹점 1:1 */
  private static List<Inspection__c> insertSources(Integer count) {
    return TestDataFactory.createInspections(
      TestDataFactory.createFranchises(count, true),
      1,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      Date.today().addDays(-1),
      true
    );
  }

  /** 기간 없는 승인대기 페널티 — insert하지 않는다. source가 null이면 가맹점은 호출자가 채운다 */
  private static Penalty__c newPenalty(
    Inspection__c source,
    String penaltyType
  ) {
    return new Penalty__c(
      Franchise__c = source?.Franchise__c,
      SourceInspection__c = source?.Id,
      PenaltyType__c = penaltyType,
      Status__c = PenaltyService.STATUS_PENDING,
      Reason__c = '테스트 — 연속 불합격'
    );
  }

  private static Penalty__c getPenalty(Id penaltyId) {
    return [
      SELECT Name, StartDate__c, EndDate__c
      FROM Penalty__c
      WHERE Id = :penaltyId
    ];
  }
}
