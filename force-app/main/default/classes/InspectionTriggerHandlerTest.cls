/* ======================================================================================
 * @description : 점검 트리거 규칙(상태 전이 · 판정 · 최근 정기점검일)을 검증하는 테스트 클래스
 * @testTarget  : InspectionTriggerHandler
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.11   Kai        Created     최초 작성 (초안: 정상 · 불허 · 벌크 200건)
 *  2026.10.12   Kai        Updated     D6 최근 정기점검일 테스트 T-09~T-16 추가 (TestDataFactory 사용)
 *  2026.10.14   Kai        Updated     SV 계정(runAs)으로 점검완료 저장 시 최근 정기점검일 갱신 테스트 추가
 *  2026.10.14   Kai        Updated     createSvUser를 TestDataFactory로 이동 (CorrectiveActionControllerTest와 공유)
 *  2026.10.18   Kai        Updated     필수 미흡 점수를 항목 미흡 기준(배점 × 0.6)에 맞춤 — 미흡은 결과 항목 트리거가 판정
 *  2026.10.18   Kai        Updated     정기점검 생성 시 결과 항목 자동 생성 테스트 5건 추가(불시 · 이관 · 중복 · 벌크 200 · SV)(D11)
 *  2026.10.18   Kai        Updated     시정조치 생성 → 점검 시정중 자동 전환(Flow) 테스트 3건 추가(D11)
 *  2026.10.19   Kai        Updated     시정조치 벌크 200건을 결과 항목마다 1건으로 변경 — 진행 중 시정조치 중복 차단 반영
 * ======================================================================================
 *  @see         : Inspection.trigger, FranchiseInspectionDateService.cls, InspectionService.cls
 *  @note        : 관리자로만 돌던 테스트가 SV의 FLS(최근 정기점검일 읽기 전용) 문제를 못 잡았다 → runAs 시나리오 추가
 * ======================================================================================*/
@isTest
private class InspectionTriggerHandlerTest {
  private static final Id REGULAR_RT_ID = Schema.SObjectType.Inspection__c
    .getRecordTypeInfosByDeveloperName()
    .get('Regular')
    .getRecordTypeId();
  private static final Id UNANNOUNCED_RT_ID = Schema.SObjectType.Inspection__c
    .getRecordTypeInfosByDeveloperName()
    .get('Unannounced')
    .getRecordTypeId();

  @TestSetup
  static void setupData() {
    insert new List<Account>{
      new Account(Name = '테스트가맹점A', StoreCode__c = 'TEST-A'),
      new Account(Name = '테스트가맹점B', StoreCode__c = 'TEST-B')
    };
  }

  // ---------------------------------------------------------------- 상태 전이

  @isTest
  static void allowsValidStatusTransition() {
    Inspection__c ins = newInspection(
      getStore('TEST-A'),
      '점검완료',
      REGULAR_RT_ID,
      null
    );
    insert ins;

    Test.startTest();
    ins.Status__c = '시정중';
    Database.SaveResult result = Database.update(ins, false);
    Test.stopTest();

    Assert.isTrue(result.isSuccess(), '점검완료 → 시정중은 허용되어야 한다');
    Assert.areEqual(
      '시정중',
      [SELECT Status__c FROM Inspection__c WHERE Id = :ins.Id].Status__c
    );
  }

  @isTest
  static void blocksInvalidStatusTransition() {
    Inspection__c ins = newInspection(
      getStore('TEST-A'),
      '종료',
      REGULAR_RT_ID,
      null
    );
    insert ins;

    Test.startTest();
    ins.Status__c = '점검예정';
    Database.SaveResult result = Database.update(ins, false);
    Test.stopTest();

    // 1) 저장이 실패했는가 — 먼저 확인해야 2)에서 getErrors()[0]이 빈 목록 오류(ListException)로 터지지 않는다
    Assert.isFalse(result.isSuccess(), '종료 → 점검예정은 차단되어야 한다');

    // 2) 다른 이유(Validation Rule · 권한 등)가 아니라 상태 전이 규칙 때문에 막혔는가
    Database.Error error = result.getErrors()[0];
    Assert.isTrue(
      error.getMessage().contains('바꿀 수 없습니다'),
      '상태 전이 오류 메시지여야 한다. 실제: ' + error.getMessage()
    );

    // 3) 오류가 상태 필드에 붙었는가 — 화면에서 상태 필드 아래에 메시지가 보이는 근거
    Assert.isTrue(
      error.getFields().contains('Status__c'),
      '오류는 상태 필드에 표시되어야 한다. 실제: ' + error.getFields()
    );

    // 4) DB 값이 그대로인가 — 저장 실패를 응답만 믿지 않고 실제 데이터로 확인
    Assert.areEqual(
      '종료',
      [SELECT Status__c FROM Inspection__c WHERE Id = :ins.Id].Status__c,
      '차단된 저장 후에도 상태는 종료로 남아 있어야 한다'
    );
  }

  // ---------------------------------------------------------------- 판정

  @isTest
  static void judgesWhenStatusBecomesCompleted() {
    Inspection__c ins = newInspection(
      getStore('TEST-A'),
      '점검예정',
      REGULAR_RT_ID,
      null
    );
    insert ins;
    // 총점 34 / 40 = 85% → 합격, 필수 항목은 정상
    insert newResults(ins.Id, new List<Integer>{ 9, 9, 8, 8 });

    Assert.isNull(
      [SELECT Judgement__c FROM Inspection__c WHERE Id = :ins.Id].Judgement__c,
      '점검예정 단계에서는 점수가 들어와도 판정하지 않아야 한다'
    );

    Test.startTest();
    ins.Status__c = '점검완료';
    update ins;
    Test.stopTest();

    Assert.areEqual(
      '합격',
      [SELECT Judgement__c FROM Inspection__c WHERE Id = :ins.Id].Judgement__c
    );
  }

  @isTest
  static void failsWhenRequiredItemIsDeficient() {
    Inspection__c ins = newInspection(
      getStore('TEST-A'),
      '점검예정',
      REGULAR_RT_ID,
      null
    );
    insert ins;
    // 총점 35 / 40 = 87.5%여도 필수 항목이 미흡(5 < 10 × 0.6)이면 불합격 (BR-03)
    insert newResults(ins.Id, new List<Integer>{ 5, 10, 10, 10 });

    Test.startTest();
    ins.Status__c = '점검완료';
    update ins;
    Test.stopTest();

    Assert.areEqual(
      '불합격',
      [SELECT Judgement__c FROM Inspection__c WHERE Id = :ins.Id].Judgement__c
    );
  }

  // ---------------------------------------------------------------- 최근 정기점검일

  @isTest
  static void recalculatesLastRegularInspectionDate() {
    Account storeA = getStore('TEST-A');
    Account storeB = getStore('TEST-B');
    Date regularDate = Date.newInstance(2026, 10, 1);

    Test.startTest();
    Inspection__c regular = newInspection(
      storeA,
      '점검완료',
      REGULAR_RT_ID,
      regularDate
    );
    insert regular;
    Assert.areEqual(
      regularDate,
      getLastDate(storeA.Id),
      '정기점검 생성 시 날짜가 들어가야 한다'
    );

    insert newInspection(
      storeA,
      '종료',
      UNANNOUNCED_RT_ID,
      Date.newInstance(2026, 10, 5)
    );
    Assert.areEqual(
      regularDate,
      getLastDate(storeA.Id),
      '불시점검은 집계 대상이 아니다'
    );

    delete regular;
    Assert.isNull(
      getLastDate(storeA.Id),
      '유일한 정기점검을 삭제하면 null이어야 한다'
    );

    undelete regular;
    Assert.areEqual(
      regularDate,
      getLastDate(storeA.Id),
      '복원하면 날짜가 돌아와야 한다'
    );

    regular.Franchise__c = storeB.Id;
    update regular;
    Test.stopTest();

    Assert.isNull(
      getLastDate(storeA.Id),
      '점검이 빠져나간 이전 가맹점은 다시 계산되어야 한다'
    );
    Assert.areEqual(
      regularDate,
      getLastDate(storeB.Id),
      '점검이 들어온 새 가맹점도 계산되어야 한다'
    );
  }

  // ---------------------------------------------------------------- 벌크 200건

  @isTest
  static void handles200InspectionsInOneTransaction() {
    List<Account> stores = new List<Account>{
      getStore('TEST-A'),
      getStore('TEST-B')
    };
    List<Inspection__c> inspections = new List<Inspection__c>();
    for (Integer i = 0; i < 200; i++) {
      inspections.add(
        newInspection(
          stores[Math.mod(i, 2)],
          '점검예정',
          REGULAR_RT_ID,
          Date.newInstance(2026, 10, 1 + Math.mod(i, 2))
        )
      );
    }
    insert inspections;

    List<InspectionResult__c> results = new List<InspectionResult__c>();
    for (Inspection__c ins : inspections) {
      results.add(
        new InspectionResult__c(
          Inspection__c = ins.Id,
          ItemName__c = '조리 순서 준수',
          Category__c = '매뉴얼',
          MaxScore__c = 10,
          Score__c = 9
        )
      );
      ins.Status__c = '점검완료';
    }
    insert results;

    Test.startTest();
    update inspections;
    Integer queriesUsed = Limits.getQueries();
    Integer dmlUsed = Limits.getDmlStatements();
    Test.stopTest();

    // NOTE: 200건이 트리거 1회로 처리되므로 날짜 재계산 SOQL 1 · DML 1 + 이 테스트의 update 1
    Assert.isTrue(
      queriesUsed <= 1,
      '200건에서도 SOQL은 1번이어야 한다. 실제: ' + queriesUsed
    );
    Assert.isTrue(
      dmlUsed <= 2,
      '200건에서도 DML은 테스트 update 1 + 트리거 1이어야 한다. 실제: ' +
      dmlUsed
    );
    Assert.areEqual(
      200,
      [SELECT COUNT() FROM Inspection__c WHERE Judgement__c = '합격']
    );
    Assert.areEqual(Date.newInstance(2026, 10, 1), getLastDate(stores[0].Id));
    Assert.areEqual(Date.newInstance(2026, 10, 2), getLastDate(stores[1].Id));
  }

  // ---------------------------------------------------------------- D6 최근 정기점검일 (T-09 ~ T-16)
  // NOTE: 집계 대상 = Regular 레코드 유형 AND 점검예정이 아닌 점검. 가맹점은 @TestSetup의 TEST-A · TEST-B를 SOQL로 다시 조회한다

  // T-09 정기점검(점검완료) insert → 가맹점 최근 정기점검일 세팅
  @isTest
  static void lastDate_regularInsert_set() {
    Account store = getStore('TEST-A');
    Date inspectionDate = Date.newInstance(2026, 10, 1);

    Test.startTest();
    createInspection(
      store,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      inspectionDate
    );
    Test.stopTest();

    Assert.areEqual(
      inspectionDate,
      getLastDate(store.Id),
      '정기점검 insert 시 최근 정기점검일이 세팅되어야 한다'
    );
  }

  // T-10 점검예정 상태의 정기점검 → 집계 제외
  @isTest
  static void lastDate_scheduled_excluded() {
    Account store = getStore('TEST-A');

    Test.startTest();
    createInspection(
      store,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.newInstance(2026, 10, 1)
    );
    Test.stopTest();

    Assert.isNull(
      getLastDate(store.Id),
      '점검예정은 아직 방문 전이라 집계 대상이 아니다'
    );
  }

  // T-11 불시점검 · 재점검 → 집계 제외 (Regular 레코드 유형만 대상)
  @isTest
  static void lastDate_nonRegular_excluded() {
    Account store = getStore('TEST-A');
    // WARN: 재점검은 VR ReinspectionRequiresOriginal 때문에 원 점검이 필수.
    //       원 점검을 점검예정으로 두어야 원 점검 자체가 집계되지 않는다
    Inspection__c original = createInspection(
      store,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.newInstance(2026, 10, 1)
    );

    Test.startTest();
    createInspection(
      store,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_UNANNOUNCED,
      Date.newInstance(2026, 10, 3)
    );
    Inspection__c reinspection = TestDataFactory.createInspections(
      new List<Account>{ store },
      1,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REINSPECTION,
      Date.newInstance(2026, 10, 5),
      false
    )[0];
    reinspection.OriginalInspection__c = original.Id;
    insert reinspection;
    Test.stopTest();

    Assert.isNull(
      getLastDate(store.Id),
      '불시점검 · 재점검은 점검완료여도 집계 대상이 아니다 (Regular 레코드 유형만)'
    );
  }

  // T-12 점검의 가맹점을 A → B로 변경 → 양쪽 모두 재계산
  @isTest
  static void lastDate_franchiseMoved_bothRecalculated() {
    Account storeA = getStore('TEST-A');
    Account storeB = getStore('TEST-B');
    Date inspectionDate = Date.newInstance(2026, 10, 1);
    Inspection__c ins = createInspection(
      storeA,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      inspectionDate
    );

    Test.startTest();
    update new Inspection__c(Id = ins.Id, Franchise__c = storeB.Id);
    Test.stopTest();

    Assert.isNull(
      getLastDate(storeA.Id),
      '점검이 빠져나간 가맹점은 null로 되돌아가야 한다 (옛 날짜가 남으면 안 됨)'
    );
    Assert.areEqual(
      inspectionDate,
      getLastDate(storeB.Id),
      '점검이 들어온 가맹점에 날짜가 반영되어야 한다'
    );
  }

  // T-13 점검일을 더 이른 날짜로 수정 → 최근 정기점검일도 내려감
  @isTest
  static void lastDate_dateMovedEarlier_lowered() {
    Account store = getStore('TEST-A');
    Inspection__c ins = createInspection(
      store,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      Date.newInstance(2026, 10, 10)
    );
    Date earlierDate = Date.newInstance(2026, 10, 1);

    Test.startTest();
    update new Inspection__c(Id = ins.Id, InspectionDate__c = earlierDate);
    Test.stopTest();

    // NOTE: 더 이른 날짜로 바꿔야 'MAX(기존, 새 값)'만 남기는 버그와 '다시 집계'를 구분할 수 있다
    Assert.areEqual(
      earlierDate,
      getLastDate(store.Id),
      '점검일을 앞당기면 최근 정기점검일도 다시 집계되어 내려가야 한다'
    );
  }

  // T-14 최신 정기점검 삭제 → 그다음 최근 점검일로 내려감
  @isTest
  static void lastDate_latestDeleted_fallsBack() {
    Account store = getStore('TEST-A');
    Date olderDate = Date.newInstance(2026, 10, 1);
    createInspection(
      store,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      olderDate
    );
    Inspection__c latest = createInspection(
      store,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      Date.newInstance(2026, 10, 5)
    );

    Test.startTest();
    delete latest;
    Test.stopTest();

    Assert.areEqual(
      olderDate,
      getLastDate(store.Id),
      '최신 점검을 삭제하면 남은 점검 중 가장 최근 날짜로 내려가야 한다'
    );
  }

  // T-15 삭제한 최신 정기점검 복원 → 다시 집계
  @isTest
  static void lastDate_undeleted_restored() {
    Account store = getStore('TEST-A');
    createInspection(
      store,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      Date.newInstance(2026, 10, 1)
    );
    Date latestDate = Date.newInstance(2026, 10, 5);
    Inspection__c latest = createInspection(
      store,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      latestDate
    );
    delete latest;

    Test.startTest();
    undelete latest;
    Test.stopTest();

    Assert.areEqual(
      latestDate,
      getLastDate(store.Id),
      '휴지통에서 복원한 점검이 다시 집계되어야 한다'
    );
  }

  // T-16 집계와 무관한 필드(판정)만 수정 → 가맹점 재계산 DML 없음
  @isTest
  static void lastDate_unrelatedChange_noAccountDml() {
    Account store = getStore('TEST-A');
    Date inspectionDate = Date.newInstance(2026, 10, 1);
    Inspection__c ins = createInspection(
      store,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      inspectionDate
    );

    Test.startTest();
    Integer dmlBefore = Limits.getDmlStatements();
    update new Inspection__c(Id = ins.Id, Judgement__c = '시정 필요');
    Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
    Test.stopTest();

    // NOTE: 테스트 컨텍스트는 테스트 자신의 update도 1회로 센다 → 가맹점 update가 없으면 정확히 1
    Assert.areEqual(
      1,
      dmlUsed,
      '집계에 영향 없는 수정은 가맹점 update를 일으키지 않아야 한다 (affectsDate 변경 감지)'
    );
    Assert.areEqual(
      inspectionDate,
      getLastDate(store.Id),
      '재계산을 건너뛰어도 기존 최근 정기점검일은 그대로여야 한다'
    );
  }

  // ---------------------------------------------------------------- SV 권한 (runAs)

  // SV가 정기점검을 점검완료로 저장하면 성공하고, 가맹점 최근 정기점검일도 갱신된다
  // NOTE: SV는 Account.LastRegularInspectionDate__c 편집 불가(권한 매트릭스 V1.2). 트리거가 시스템 모드로 써야 한다
  @isTest
  static void svCompletesRegularInspection_updatesLastDate() {
    User sv = TestDataFactory.createSvUser('테스트SV', true);
    Account store = getStore('TEST-A');
    Date inspectionDate = Date.newInstance(2026, 10, 1);
    Inspection__c ins = newInspection(
      store,
      TestDataFactory.STATUS_SCHEDULED,
      REGULAR_RT_ID,
      inspectionDate
    );
    ins.OwnerId = sv.Id; // DESC: SV가 자기 점검을 저장하는 상황 — 소유자라 공유 규칙과 무관하게 편집 가능
    insert ins;
    insert newResults(ins.Id, new List<Integer>{ 9, 9, 8, 8 });

    Database.SaveResult result;
    Test.startTest();
    System.runAs(sv) {
      ins.Status__c = TestDataFactory.STATUS_COMPLETED;
      result = Database.update(ins, false);
    }
    Test.stopTest();

    Assert.isTrue(
      result.isSuccess(),
      'SV의 점검완료 저장은 성공해야 한다. 실제 오류: ' + result.getErrors()
    );
    Assert.areEqual(
      inspectionDate,
      getLastDate(store.Id),
      'SV에게 편집 권한이 없는 필드여도 트리거가 최근 정기점검일을 갱신해야 한다'
    );
  }

  // ---------------------------------------------------------------- 테스트 데이터 도우미

  /** TestDataFactory로 점검 1건을 만들어 insert한다 */
  private static Inspection__c createInspection(
    Account store,
    String status,
    String recordTypeDeveloperName,
    Date inspectionDate
  ) {
    return TestDataFactory.createInspections(
      new List<Account>{ store },
      1,
      status,
      recordTypeDeveloperName,
      inspectionDate,
      true
    )[0];
  }

  // ---------------------------------------------------------------- 결과 항목 자동 생성 (D11)

  // 증명: 새 정기점검(이관번호 없음 · 점검예정)에는 사용 중 템플릿 전부가 결과 항목으로 생긴다 — 점수는 비고,
  //       스냅샷(항목명 · 배점)은 결과 항목 트리거가 채우며, 비활성 템플릿은 빠진다. 판정은 아직 없다
  @isTest
  static void newRegularInspection_createsResultsFromActiveTemplates() {
    insertTwentyTemplatesAndOneInactive();
    Inspection__c ins = newInspection(
      getStore('TEST-A'),
      '점검예정',
      REGULAR_RT_ID,
      Date.today()
    );

    Test.startTest();
    insert ins;
    Test.stopTest();

    List<InspectionResult__c> results = getResults(ins.Id);
    Assert.areEqual(
      20,
      results.size(),
      '사용 중 템플릿 20개 → 결과 20행(비활성 1개 제외)'
    );
    for (InspectionResult__c result : results) {
      Assert.isNull(result.Score__c, '점수는 비워 둔다');
      Assert.isNotNull(result.TemplateItem__c, '템플릿 Lookup');
      Assert.isNotNull(
        result.ItemName__c,
        '스냅샷 항목명은 결과 항목 트리거가 채운다'
      );
      Assert.areEqual(5, result.MaxScore__c, '스냅샷 배점');
      Assert.isFalse(result.IsDeficient__c, '점수가 없으면 판정 보류');
    }
    Inspection__c saved = [
      SELECT ruTotalScore__c, ruMaxScore__c, Judgement__c
      FROM Inspection__c
      WHERE Id = :ins.Id
    ];
    Assert.areEqual(100, saved.ruMaxScore__c, '배점 합계 100');
    Assert.areEqual(0, saved.ruTotalScore__c, '총점 0(미입력)');
    Assert.isNull(saved.Judgement__c, '점검예정이라 판정하지 않는다');
  }

  // 증명: 불시점검 · 이관번호가 있는 점검 · 점검완료로 바로 들어온 점검에는 결과를 만들지 않는다
  @isTest
  static void unannouncedMigratedOrCompleted_createsNoResults() {
    insertTwentyTemplatesAndOneInactive();
    Account store = getStore('TEST-A');
    Inspection__c unannounced = newInspection(
      store,
      '점검예정',
      UNANNOUNCED_RT_ID,
      Date.today()
    );
    Inspection__c migrated = newInspection(
      store,
      '점검예정',
      REGULAR_RT_ID,
      Date.today()
    );
    migrated.InspectionNo__c = 'MIG-TEST-0001';
    Inspection__c completed = newInspection(
      store,
      '점검완료',
      REGULAR_RT_ID,
      Date.today()
    );

    Test.startTest();
    insert new List<Inspection__c>{ unannounced, migrated, completed };
    Test.stopTest();

    Assert.areEqual(0, getResults(unannounced.Id).size(), '불시점검은 2차');
    Assert.areEqual(
      0,
      getResults(migrated.Id).size(),
      '이관번호가 있으면 이관 · 데모 데이터'
    );
    Assert.areEqual(
      0,
      getResults(completed.Id).size(),
      '점검완료로 들어온 점검에 빈 행을 붙이면 0점 불합격이 되므로 제외'
    );
  }

  // 증명: 이미 결과가 있는 점검은 같은 메서드를 다시 불러도 추가하지 않는다(없는 점검만 생성)
  @isTest
  static void existingResults_notDuplicated() {
    List<InspectionTemplateItem__c> templates = insertTwentyTemplatesAndOneInactive();
    Account store = getStore('TEST-A');
    // NOTE: 이관번호를 채워 트리거 자동 생성을 피하고, 결과 1행을 직접 넣어 둔다
    Inspection__c withResult = newInspection(
      store,
      '점검예정',
      REGULAR_RT_ID,
      Date.today()
    );
    withResult.InspectionNo__c = 'MIG-TEST-0002';
    Inspection__c withoutResult = newInspection(
      store,
      '점검예정',
      REGULAR_RT_ID,
      Date.today()
    );
    withoutResult.InspectionNo__c = 'MIG-TEST-0003';
    insert new List<Inspection__c>{ withResult, withoutResult };
    insert new InspectionResult__c(
      Inspection__c = withResult.Id,
      TemplateItem__c = templates[0].Id,
      Score__c = 5
    );

    Test.startTest();
    InspectionResultService.createPendingResults(
      new List<Inspection__c>{ withResult, withoutResult }
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      getResults(withResult.Id).size(),
      '결과가 있던 점검은 그대로 1행'
    );
    Assert.areEqual(
      20,
      getResults(withoutResult.Id).size(),
      '없던 점검만 20행'
    );
  }

  // 증명: 정기점검 200건을 한 번에 넣어도 결과 4,000행이 생기고 SOQL은 손에 꼽는다(템플릿 캐시 — 결과 트리거 20회 실행에도 재조회 없음)
  @isTest
  static void bulk200RegularInspections_createsFourThousandResults() {
    insertTwentyTemplatesAndOneInactive();
    Account store = getStore('TEST-A');
    List<Inspection__c> inspections = new List<Inspection__c>();
    for (Integer i = 0; i < 200; i++) {
      inspections.add(
        newInspection(store, '점검예정', REGULAR_RT_ID, Date.today())
      );
    }

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    Integer cpuBefore = Limits.getCpuTime();
    insert inspections;
    Integer cpuUsed = Limits.getCpuTime() - cpuBefore;
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    // NOTE: CPU 실측값은 ApexTestResultLimits(Tooling)로도 확인한다 — 아래는 한도(10,000ms)와 거리가 있는지만 본다
    System.debug(
      LoggingLevel.ERROR,
      '>>> 200건 자동 생성 CPU ' + cpuUsed + 'ms · SOQL ' + queriesUsed
    );
    Assert.areEqual(
      4000,
      [
        SELECT COUNT()
        FROM InspectionResult__c
        WHERE Inspection__c IN :inspections
      ],
      '200 × 20 = 4,000행'
    );
    Assert.isTrue(
      queriesUsed <= 5,
      'SOQL은 결과 확인 1 + 템플릿 1 정도여야 한다. 실제: ' + queriesUsed
    );
    Assert.isTrue(
      cpuUsed < 8000,
      'CPU 한도(10,000ms)에 여유가 있어야 한다. 실제: ' + cpuUsed + 'ms'
    );
  }

  // 증명: 실제 입력자인 SV가 자기 가맹점에 정기점검을 만들어도 결과 20행이 SV 이름으로 생긴다
  @isTest
  static void svCreatesRegularInspection_resultsCreated() {
    insertTwentyTemplatesAndOneInactive();
    User sv = TestDataFactory.createSvUser('자동생성테스트SV', true);
    Account store = getStore('TEST-A');
    update new Account(Id = store.Id, OwnerId = sv.Id);
    Inspection__c ins = newInspection(
      store,
      '점검예정',
      REGULAR_RT_ID,
      Date.today()
    );

    Test.startTest();
    System.runAs(sv) {
      insert ins;
    }
    Test.stopTest();

    List<InspectionResult__c> results = getResults(ins.Id);
    Assert.areEqual(20, results.size(), 'SV가 만들어도 20행');
    Assert.areEqual(
      sv.Id,
      results[0].CreatedById,
      '결과는 SV가 만든 것으로 남는다'
    );
    Assert.isNotNull(results[0].ItemName__c, '스냅샷 복사');
  }

  /** 새 점검표와 같은 사용 중 템플릿 20개(5점, 앞 6개 위생 필수) + 비활성 1개 */
  private static List<InspectionTemplateItem__c> insertTwentyTemplatesAndOneInactive() {
    List<InspectionTemplateItem__c> templates = TestDataFactory.createTemplateItems(
      20,
      6,
      5,
      true
    );
    insert new InspectionTemplateItem__c(
      Name = 'TEST비활성항목',
      Category__c = '서비스',
      MaxScore__c = 5,
      IsActive__c = false,
      SortOrder__c = 99
    );
    return templates;
  }

  private static List<InspectionResult__c> getResults(Id inspectionId) {
    return [
      SELECT
        Score__c,
        TemplateItem__c,
        ItemName__c,
        MaxScore__c,
        IsDeficient__c,
        CreatedById
      FROM InspectionResult__c
      WHERE Inspection__c = :inspectionId
    ];
  }

  // ---------------------------------------------------------------- 시정조치 생성 → 시정중 자동 (Flow CorrectiveAction_AfterSave)

  // 증명: 점검완료 점검에 시정조치를 추가하면 점검 상태가 시정중으로 바뀐다(전이 검증은 이 트리거가 통과시킨다)
  @isTest
  static void correctiveActionOnCompleted_movesInspectionToCorrecting() {
    Inspection__c ins = insertInspectionWithResult(
      TestDataFactory.STATUS_COMPLETED,
      1
    )[0];

    Test.startTest();
    TestDataFactory.createCorrectiveActions(
      getResultsOf(ins.Id),
      1,
      '요청',
      Date.today().addDays(7),
      true
    );
    Test.stopTest();

    Assert.areEqual(
      '시정중',
      [SELECT Status__c FROM Inspection__c WHERE Id = :ins.Id].Status__c,
      '점검완료 → 시정중'
    );
  }

  // 증명: 이미 시정중인 점검에 시정조치를 더해도 상태는 그대로이고 오류가 나지 않는다
  @isTest
  static void correctiveActionOnCorrecting_keepsStatusWithoutError() {
    Inspection__c ins = insertInspectionWithResult('시정중', 1)[0];

    Test.startTest();
    List<Database.SaveResult> saved = Database.insert(
      TestDataFactory.createCorrectiveActions(
        getResultsOf(ins.Id),
        1,
        '요청',
        Date.today().addDays(7),
        false
      ),
      false
    );
    Test.stopTest();

    Assert.isTrue(
      saved[0].isSuccess(),
      '오류 없이 저장: ' + saved[0].getErrors()
    );
    Assert.areEqual(
      '시정중',
      [SELECT Status__c FROM Inspection__c WHERE Id = :ins.Id].Status__c,
      '상태 그대로'
    );
  }

  // 증명: 점검 2건에 시정조치 200건을 한 번에 넣어도 두 점검 모두 시정중이 되고, 같은 점검을 여러 번 저장하지 않는다
  @isTest
  static void bulk200CorrectiveActionsOnTwoInspections_eachMovedOnce() {
    // NOTE: 같은 결과 항목에는 진행 중 시정조치를 1건만 둘 수 있다(중복 차단) — 점검 2건 × 결과 항목 100개 × 시정조치 1건
    List<Inspection__c> inspections = TestDataFactory.createInspections(
      TestDataFactory.createFranchises(2, true),
      1,
      TestDataFactory.STATUS_COMPLETED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    );
    List<InspectionTemplateItem__c> templates = TestDataFactory.createTemplateItems(
      100,
      0,
      10,
      true
    );
    List<Decimal> scores = new List<Decimal>();
    for (Integer i = 0; i < templates.size(); i++) {
      scores.add(5);
    }
    List<InspectionResult__c> results = new List<InspectionResult__c>();
    for (Inspection__c ins : inspections) {
      results.addAll(
        TestDataFactory.createResults(ins, templates, scores, false)
      );
    }
    insert results;
    Set<Id> inspectionIds = new Map<Id, Inspection__c>(inspections).keySet();

    Test.startTest();
    Integer dmlBefore = Limits.getDmlStatements();
    TestDataFactory.createCorrectiveActions(
      results,
      1,
      '요청',
      Date.today().addDays(7),
      true
    );
    Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
    Test.stopTest();

    Assert.areEqual(
      200,
      [
        SELECT COUNT()
        FROM CorrectiveAction__c
        WHERE InspectionResult__c IN :results
      ],
      '시정조치 200건'
    );
    for (Inspection__c saved : [
      SELECT Status__c
      FROM Inspection__c
      WHERE Id IN :inspectionIds
    ]) {
      Assert.areEqual('시정중', saved.Status__c, '두 점검 모두 시정중');
    }
    // NOTE: insert 1 + Flow 점검 update 1(일괄) — 점검별 · 시정조치별로 DML이 늘지 않는다
    Assert.isTrue(
      dmlUsed <= 2,
      '시정조치 insert 1 + 점검 update 1이어야 한다. 실제: ' + dmlUsed
    );
  }

  /** 지정 상태의 정기점검(가맹점 1:1)마다 결과 항목 1건(10점 중 5점 — 미흡)을 만든다 */
  private static List<Inspection__c> insertInspectionWithResult(
    String status,
    Integer count
  ) {
    List<Inspection__c> inspections = TestDataFactory.createInspections(
      TestDataFactory.createFranchises(count, true),
      1,
      status,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    );
    List<InspectionTemplateItem__c> templates = TestDataFactory.createTemplateItems(
      1,
      0,
      10,
      true
    );
    List<InspectionResult__c> results = new List<InspectionResult__c>();
    for (Inspection__c ins : inspections) {
      results.addAll(
        TestDataFactory.createResults(
          ins,
          templates,
          new List<Decimal>{ 5 },
          false
        )
      );
    }
    insert results;
    return inspections;
  }

  private static List<InspectionResult__c> getResultsOf(Id inspectionId) {
    return [
      SELECT Id
      FROM InspectionResult__c
      WHERE Inspection__c = :inspectionId
    ];
  }

  private static Account getStore(String storeCode) {
    return [SELECT Id FROM Account WHERE StoreCode__c = :storeCode];
  }

  private static Date getLastDate(Id franchiseId) {
    return [
      SELECT LastRegularInspectionDate__c
      FROM Account
      WHERE Id = :franchiseId
    ]
    .LastRegularInspectionDate__c;
  }

  private static Inspection__c newInspection(
    Account store,
    String status,
    Id recordTypeId,
    Date inspectionDate
  ) {
    return new Inspection__c(
      Franchise__c = store.Id,
      Status__c = status,
      RecordTypeId = recordTypeId,
      InspectionDate__c = inspectionDate
    );
  }

  /** 템플릿과 같은 4항목(배점 10). 첫 번째가 필수. 미흡은 결과 항목 트리거가 점수로 판정한다(점수 < 배점 × 0.6) */
  private static List<InspectionResult__c> newResults(
    Id inspectionId,
    List<Integer> scores
  ) {
    return new List<InspectionResult__c>{
      new InspectionResult__c(
        Inspection__c = inspectionId,
        ItemName__c = '냉장고 온도 관리',
        Category__c = '위생',
        MaxScore__c = 10,
        Score__c = scores[0],
        IsRequired__c = true
      ),
      new InspectionResult__c(
        Inspection__c = inspectionId,
        ItemName__c = '주방 바닥 청결',
        Category__c = '위생',
        MaxScore__c = 10,
        Score__c = scores[1]
      ),
      new InspectionResult__c(
        Inspection__c = inspectionId,
        ItemName__c = '고객 응대 인사',
        Category__c = '서비스',
        MaxScore__c = 10,
        Score__c = scores[2]
      ),
      new InspectionResult__c(
        Inspection__c = inspectionId,
        ItemName__c = '조리 순서 준수',
        Category__c = '매뉴얼',
        MaxScore__c = 10,
        Score__c = scores[3]
      )
    };
  }

  // ───────── 아래는 Kai 작성 구역 (T-01~T-08) — 건드리지 말 것 ─────────

  // T-02 점검완료 → 점검예정 (역방향) 은 차단되어야 한다
  @IsTest
  static void statusTransition_reverseFromCompleted_addsError() {
    // given: 점검완료 상태인 점검 1건
    //        (@TestSetup이 만든 데이터를 SOQL로 조회해서 쓰거나,
    //         TestDataFactory로 점검예정 1건 만들고 점검완료로 한 번 올린다)
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    Inspection__c ins = TestDataFactory.createInspections(
      new List<Account>{ franchise },
      1,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    )[0];
    ins.Status__c = '점검완료';
    update ins;

    Test.startTest();
    ins.Status__c = '점검예정'; // 역방향
    Database.SaveResult result = Database.update(ins, false); // ← 부분 저장
    Test.stopTest();

    Assert.isFalse(
      result.isSuccess(),
      '점검완료에서 점검예정으로 되돌리는 전이는 막혀야 함'
    );

    Assert.isTrue(
      result.getErrors()[0].getMessage().contains('바꿀 수 없습니다'),
      '전이 불가 사유가 사용자에게 전달되어야 함'
    );

    Assert.areEqual(
      'Status__c',
      result.getErrors()[0].getFields()[0],
      '오류는 상태 필드에 걸려야 화면에서 어느 필드가 문제인지 보인다'
    );
  }
}
