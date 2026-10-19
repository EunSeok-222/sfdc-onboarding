/* ======================================================================================
 * @description : 점검 결과 입력 화면(SC-02) 컨트롤러의 조회 순서 · 공유 범위 · 일괄 저장 · 오류 메시지를 검증하는 테스트 클래스
 * @testTarget  : InspectionResultController
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 분류 · 정렬 순서, SV 공유 범위, 200건 DML 1, 배점 초과 · 조회전용 FLS, 빈 Id
 *  2026.10.19   Kai        Updated     시정중 점검 읽기 전용 · 점수 저장 차단(검증 규칙 ScoreLockedAfterCompletion), 점검완료는 수정 가능
 * ======================================================================================*/
@IsTest
private class InspectionResultControllerTest {
  private static final String PROFILE_READ_ONLY = '가맹점점검 조회전용(경영진)';

  // 증명: 분류는 위생 → 서비스 → 매뉴얼, 같은 분류 안은 템플릿 정렬 순서(없으면 뒤로). 필수 · 미흡 · 배점이 함께 온다
  @IsTest
  static void getResults_sortedByCategoryThenTemplateOrder() {
    Inspection__c ins = insertInspection(
      null,
      TestDataFactory.STATUS_SCHEDULED
    );
    List<InspectionTemplateItem__c> templates = new List<InspectionTemplateItem__c>{
      template('매뉴얼A', '매뉴얼', 10, false),
      template('서비스A', '서비스', 20, false),
      template('위생B', '위생', 30, true),
      template('위생A', '위생', 5, false)
    };
    insert templates;
    insert TestDataFactory.createResults(
      ins,
      templates,
      new List<Decimal>{ 5, 1, 5, 5 },
      false
    );
    // NOTE: 템플릿 없는 이관 행 — 같은 분류(위생) 안에서 맨 뒤
    insert new InspectionResult__c(
      Inspection__c = ins.Id,
      ItemName__c = '위생-이관',
      Category__c = '위생',
      MaxScore__c = 5,
      Score__c = 5
    );

    Test.startTest();
    InspectionResultController.ResultSheet sheet = InspectionResultController.getResults(
      ins.Id
    );
    Test.stopTest();

    List<String> names = new List<String>();
    for (
      InspectionResultController.InspectionResultWrapper row : sheet.results
    ) {
      names.add(row.itemName);
    }
    Assert.areEqual(
      new List<String>{ '위생A', '위생B', '위생-이관', '서비스A', '매뉴얼A' },
      names,
      '분류 → 템플릿 정렬 순서 → 정렬 없는 행'
    );
    Assert.areEqual(
      TestDataFactory.STATUS_SCHEDULED,
      sheet.inspectionStatus,
      '상위 점검 상태'
    );
    Assert.isFalse(sheet.isReadOnly, '관리자 · 점검예정은 입력 가능');
    InspectionResultController.InspectionResultWrapper service = sheet.results[3];
    Assert.areEqual(1, service.score, '점수');
    Assert.areEqual(5, service.maxScore, '배점');
    Assert.isTrue(service.isDeficient, '1 < 5 × 0.6 → 미흡(트리거 판정)');
    Assert.isTrue(sheet.results[1].isRequired, '위생B는 필수');
  }

  // 증명: SV는 자기 점검의 결과만 본다 — 다른 SV 점검 Id는 빈 목록(예외 없음)
  @IsTest
  static void svSeesOwnInspectionOnly() {
    User mine = TestDataFactory.createSvUser('결과입력SV본인', false);
    User other = TestDataFactory.createSvUser('결과입력SV타인', false);
    insert new List<User>{ mine, other };
    List<Inspection__c> inspections = insertInspections(
      new List<Id>{ mine.Id, other.Id },
      TestDataFactory.STATUS_SCHEDULED
    );
    Inspection__c own = inspections[0];
    Inspection__c others = inspections[1];
    List<InspectionTemplateItem__c> templates = TestDataFactory.createTemplateItems(
      2,
      1,
      5,
      true
    );
    insert TestDataFactory.createResults(
      own,
      templates,
      new List<Decimal>{ 5, 5 },
      false
    );
    insert TestDataFactory.createResults(
      others,
      templates,
      new List<Decimal>{ 5, 5 },
      false
    );

    InspectionResultController.ResultSheet ownSheet;
    InspectionResultController.ResultSheet othersSheet;
    Test.startTest();
    System.runAs(mine) {
      ownSheet = InspectionResultController.getResults(own.Id);
      othersSheet = InspectionResultController.getResults(others.Id);
    }
    Test.stopTest();

    Assert.areEqual(2, ownSheet.results.size(), '자기 점검 2행');
    Assert.isFalse(ownSheet.isReadOnly, 'SV는 점수 입력 가능');
    Assert.areEqual(
      0,
      othersSheet.results.size(),
      '다른 SV 점검은 보이지 않는다'
    );
    Assert.isNull(othersSheet.inspectionStatus, '상태도 알려 주지 않는다');
  }

  // 증명: 200건 점수 저장은 DML 1번이고 값이 모두 반영된다
  @IsTest
  static void saveResults_200Rows_oneDml() {
    Inspection__c ins = insertInspection(
      null,
      TestDataFactory.STATUS_SCHEDULED
    );
    List<InspectionTemplateItem__c> templates = TestDataFactory.createTemplateItems(
      200,
      0,
      5,
      true
    );
    List<Decimal> empty = new List<Decimal>();
    for (Integer i = 0; i < 200; i++) {
      empty.add(null);
    }
    insert TestDataFactory.createResults(ins, templates, empty, false);
    List<Id> ids = new List<Id>();
    List<Decimal> scores = new List<Decimal>();
    for (InspectionResult__c result : [
      SELECT Id
      FROM InspectionResult__c
      WHERE Inspection__c = :ins.Id
    ]) {
      ids.add(result.Id);
      scores.add(3);
    }

    Test.startTest();
    Integer dmlBefore = Limits.getDmlStatements();
    InspectionResultController.saveResults(ids, scores);
    Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
    Test.stopTest();

    Assert.areEqual(1, dmlUsed, '200건이어도 update 1번');
    Assert.areEqual(
      200,
      [
        SELECT COUNT()
        FROM InspectionResult__c
        WHERE Inspection__c = :ins.Id AND Score__c = 3
      ],
      '200건 저장'
    );
  }

  // 증명: 시정 단계(시정중)부터는 읽기 전용이고 점수 저장이 검증 규칙(ScoreLockedAfterCompletion)으로 막힌다. 점검완료는 고칠 수 있다
  @IsTest
  static void correctingInspection_isReadOnlyAndScoreLocked() {
    List<Inspection__c> inspections = insertInspections(
      new List<Id>{ null, null },
      TestDataFactory.STATUS_COMPLETED
    );
    Inspection__c completed = inspections[0];
    Inspection__c correcting = inspections[1];
    List<InspectionTemplateItem__c> items = TestDataFactory.createTemplateItems(
      1,
      0,
      5,
      true
    );
    List<InspectionResult__c> results = new List<InspectionResult__c>();
    results.addAll(
      TestDataFactory.createResults(
        completed,
        items,
        new List<Decimal>{ 5 },
        false
      )
    );
    results.addAll(
      TestDataFactory.createResults(
        correcting,
        items,
        new List<Decimal>{ 5 },
        false
      )
    );
    insert results;
    // NOTE: 점검완료 → 시정중은 허용 전이. 결과 항목을 만든 뒤에 시정 단계로 보낸다
    update new Inspection__c(Id = correcting.Id, Status__c = '시정중');

    AuraHandledException locked;
    Test.startTest();
    InspectionResultController.ResultSheet completedSheet = InspectionResultController.getResults(
      completed.Id
    );
    InspectionResultController.ResultSheet correctingSheet = InspectionResultController.getResults(
      correcting.Id
    );
    // DESC: 점검완료는 아직 고칠 수 있다(판정 재계산) — 같은 트랜잭션에서 저장이 통과하는지 함께 본다
    InspectionResultController.saveResults(
      new List<Id>{ results[0].Id },
      new List<Decimal>{ 4 }
    );
    try {
      InspectionResultController.saveResults(
        new List<Id>{ results[1].Id },
        new List<Decimal>{ 4 }
      );
    } catch (AuraHandledException e) {
      locked = e;
    }
    Test.stopTest();

    Assert.isFalse(completedSheet.isReadOnly, '점검완료는 점수를 고칠 수 있다');
    Assert.isTrue(correctingSheet.isReadOnly, '시정중은 읽기 전용');
    Assert.areEqual(
      4,
      [SELECT Score__c FROM InspectionResult__c WHERE Id = :results[0].Id]
      .Score__c,
      '점검완료 점수는 저장된다'
    );
    Assert.isNotNull(locked, '시정중 점수 저장은 막혀야 한다');
    Assert.isTrue(
      locked.getMessage().contains('시정 단계부터는 점수를 고칠 수 없습니다'),
      '검증 규칙 문구 그대로: ' + locked.getMessage()
    );
    Assert.areEqual(
      5,
      [SELECT Score__c FROM InspectionResult__c WHERE Id = :results[1].Id]
      .Score__c,
      '시정중 점수는 그대로'
    );
  }

  // 증명: 배점보다 큰 점수는 검증 규칙(ScoreWithinMaxScore) 메시지 그대로 화면에 돌아간다
  @IsTest
  static void saveResults_overMaxScore_returnsValidationMessage() {
    Inspection__c ins = insertInspection(
      null,
      TestDataFactory.STATUS_SCHEDULED
    );
    insert TestDataFactory.createResults(
      ins,
      TestDataFactory.createTemplateItems(1, 0, 5, true),
      new List<Decimal>{ 5 },
      false
    );
    Id resultId = [
      SELECT Id
      FROM InspectionResult__c
      WHERE Inspection__c = :ins.Id
    ]
    .Id;

    AuraHandledException caught;
    Test.startTest();
    try {
      InspectionResultController.saveResults(
        new List<Id>{ resultId },
        new List<Decimal>{ 6 }
      );
    } catch (AuraHandledException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(caught, '배점 초과는 저장되지 않는다');
    Assert.isTrue(
      caught.getMessage().contains('배점 이하'),
      '검증 규칙 문구 그대로: ' + caught.getMessage()
    );
    Assert.areEqual(
      5,
      [SELECT Score__c FROM InspectionResult__c WHERE Id = :resultId].Score__c,
      '값은 그대로'
    );
  }

  // 증명: 조회전용(경영진) 사용자는 읽기 전용으로 받고, 저장을 시도해도 권한(USER_MODE)으로 거부된다
  @IsTest
  static void readOnlyUser_isReadOnlyAndSaveRejected() {
    User viewer = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = :PROFILE_READ_ONLY]
      .Id,
      LastName = '결과입력조회전용',
      Alias = 'tview',
      Email = 'test.viewer@example.com',
      Username = 'test.viewer.' +
        String.valueOf(Crypto.getRandomInteger()).replace('-', '') +
        '@example.com',
      TimeZoneSidKey = 'Asia/Seoul',
      LocaleSidKey = 'ko_KR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'ko'
    );
    insert viewer;
    // NOTE: 점검 소유자로 두어 레코드는 볼 수 있게 하고, 점수 편집 권한(FLS · 오브젝트)만 없는 상태를 만든다
    Inspection__c ins = insertInspection(
      viewer.Id,
      TestDataFactory.STATUS_SCHEDULED
    );
    insert TestDataFactory.createResults(
      ins,
      TestDataFactory.createTemplateItems(1, 0, 5, true),
      new List<Decimal>{ 5 },
      false
    );
    Id resultId = [
      SELECT Id
      FROM InspectionResult__c
      WHERE Inspection__c = :ins.Id
    ]
    .Id;

    InspectionResultController.ResultSheet sheet;
    AuraHandledException caught;
    Test.startTest();
    System.runAs(viewer) {
      sheet = InspectionResultController.getResults(ins.Id);
      try {
        InspectionResultController.saveResults(
          new List<Id>{ resultId },
          new List<Decimal>{ 1 }
        );
      } catch (AuraHandledException e) {
        caught = e;
      }
    }
    Test.stopTest();

    Assert.areEqual(1, sheet.results.size(), '조회는 된다');
    Assert.isTrue(sheet.isReadOnly, '점수 편집 권한이 없으면 읽기 전용');
    Assert.isNotNull(caught, '저장은 권한으로 거부된다');
    Assert.areEqual(
      5,
      [SELECT Score__c FROM InspectionResult__c WHERE Id = :resultId].Score__c,
      '값은 그대로'
    );
  }

  // 증명: 종료된 점검은 읽기 전용, 빈 Id · 빈 목록은 아무것도 하지 않는다, 목록 길이가 다르면 거부
  @IsTest
  static void closedOrEmptyInputs_handled() {
    Inspection__c closed = insertInspection(null, '종료');

    Test.startTest();
    InspectionResultController.ResultSheet closedSheet = InspectionResultController.getResults(
      closed.Id
    );
    InspectionResultController.ResultSheet blankSheet = InspectionResultController.getResults(
      null
    );
    Integer dmlBefore = Limits.getDmlStatements();
    InspectionResultController.saveResults(null, null);
    InspectionResultController.saveResults(new List<Id>(), new List<Decimal>());
    Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
    AuraHandledException mismatch;
    try {
      InspectionResultController.saveResults(
        new List<Id>{ closed.Id },
        new List<Decimal>()
      );
    } catch (AuraHandledException e) {
      mismatch = e;
    }
    Test.stopTest();

    Assert.isTrue(closedSheet.isReadOnly, '종료 점검은 읽기 전용');
    Assert.areEqual(0, blankSheet.results.size(), '빈 Id → 빈 목록');
    Assert.isTrue(blankSheet.isReadOnly, '빈 Id → 읽기 전용');
    Assert.areEqual(0, dmlUsed, '빈 입력은 저장하지 않는다');
    Assert.isNotNull(mismatch, '항목 · 점수 개수가 다르면 거부');
  }

  // ------------------------------------------------------------------ helpers

  private static Inspection__c insertInspection(Id ownerId, String status) {
    return insertInspections(new List<Id>{ ownerId }, status)[0];
  }

  // NOTE: createFranchises는 호출마다 사업자번호를 0번부터 매겨 두 번 부르면 중복 규칙에 걸린다 → 한 번에 만든다
  private static List<Inspection__c> insertInspections(
    List<Id> ownerIds,
    String status
  ) {
    List<Inspection__c> inspections = TestDataFactory.createInspections(
      TestDataFactory.createFranchises(ownerIds.size(), true),
      1,
      status,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      false
    );
    for (Integer i = 0; i < inspections.size(); i++) {
      if (ownerIds[i] != null) {
        inspections[i].OwnerId = ownerIds[i];
      }
    }
    insert inspections;
    return inspections;
  }

  private static InspectionTemplateItem__c template(
    String name,
    String category,
    Integer sortOrder,
    Boolean required
  ) {
    return new InspectionTemplateItem__c(
      Name = name,
      Category__c = category,
      MaxScore__c = 5,
      IsRequired__c = required,
      IsActive__c = true,
      SortOrder__c = sortOrder
    );
  }
}
