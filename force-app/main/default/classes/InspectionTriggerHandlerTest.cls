/* ======================================================================================
 * @description : 점검 트리거 규칙(상태 전이 · 판정 · 최근 정기점검일)을 검증하는 테스트 클래스
 * @testTarget  : InspectionTriggerHandler
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.11   Kai        Created     최초 작성 (초안: 정상 · 불허 · 벌크 200건)
 * ======================================================================================
 *  @see         : Inspection.trigger, FranchiseInspectionDateService.cls, InspectionService.cls
 *  @note        : SV 권한(runAs) 시나리오와 InspectionService.judgeInspections는 D6에서 보강
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

    // TODO(Kai): 아래 3가지를 Assert로 확인한다
    //   1) 저장이 실패했는지              → result.isSuccess()
    //   2) 오류 메시지가 우리가 만든 문구인지 → result.getErrors()[0].getMessage()에 '바꿀 수 없습니다' 포함
    //   3) DB의 상태가 그대로 '종료'인지   → SOQL로 다시 조회
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
    insert newResults(ins.Id, new List<Integer>{ 9, 9, 8, 8 }, false);

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
    // 총점 36 / 40 = 90%여도 필수 항목이 미흡이면 불합격 (BR-03)
    insert newResults(ins.Id, new List<Integer>{ 6, 10, 10, 10 }, true);

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

  // ---------------------------------------------------------------- 테스트 데이터 도우미

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

  /** 템플릿과 같은 4항목(배점 10). requiredDeficient가 true면 필수 항목(첫 번째)을 미흡으로 둔다 */
  private static List<InspectionResult__c> newResults(
    Id inspectionId,
    List<Integer> scores,
    Boolean requiredDeficient
  ) {
    return new List<InspectionResult__c>{
      new InspectionResult__c(
        Inspection__c = inspectionId,
        ItemName__c = '냉장고 온도 관리',
        Category__c = '위생',
        MaxScore__c = 10,
        Score__c = scores[0],
        IsRequired__c = true,
        IsDeficient__c = requiredDeficient
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
}
