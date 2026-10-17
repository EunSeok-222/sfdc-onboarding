/* ======================================================================================
 * @description : 점검 결과 항목 트리거의 스냅샷 복사(BR-11)와 미흡 판정(BR-03)을 검증하는 테스트 클래스
 * @testTarget  : InspectionResult.trigger, InspectionResultTriggerHandler, InspectionResultService,
 *                InspectionRuleSelector.getDeficiencyRate
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 경계값(5점 중 2 · 3) · 스냅샷 복사 · 템플릿 변경 후 불변 · 템플릿 없는 insert ·
 *                                      필수 미흡 1개 + 총점 97 → 불합격 · 벌크 200 · SV runAs (D1)
 * ======================================================================================
 *  @see         : InspectionResultService.cls
 *  @note        : 항목 미흡 기준은 배포된 InspectionRule__mdt Default(0.6)를 쓴다. 값이 비는 경우만 ruleOverride로 흉내 낸다
 * ======================================================================================*/
@IsTest
private class InspectionResultTriggerHandlerTest {
  private static final Decimal MAX_SCORE = 5;

  // 증명: 템플릿을 지정해 insert하면 입력한 스냅샷 값과 무관하게 템플릿의 항목명 · 분류 · 배점 · 필수가 복사되고,
  //       복사한 배점으로 미흡이 판정된다(순서: 복사 → 판정)
  @IsTest
  static void insertWithTemplate_copiesSnapshotThenJudges() {
    InspectionTemplateItem__c template = TestDataFactory.createTemplateItems(
      1,
      1,
      MAX_SCORE,
      true
    )[0];
    Inspection__c ins = insertScheduledInspection();

    Test.startTest();
    insert new InspectionResult__c(
      Inspection__c = ins.Id,
      TemplateItem__c = template.Id,
      Score__c = 2,
      // NOTE: 일부러 틀린 스냅샷 — 템플릿 값으로 덮여야 한다. 배점이 99로 남으면 2점은 미흡이 아니게 된다
      ItemName__c = '잘못 입력한 항목명',
      Category__c = '매뉴얼',
      MaxScore__c = 99,
      IsRequired__c = false
    );
    Test.stopTest();

    InspectionResult__c saved = getOnlyResult(ins.Id);
    Assert.areEqual(template.Name, saved.ItemName__c, '항목명 복사');
    Assert.areEqual('위생', saved.Category__c, '분류 복사');
    Assert.areEqual(MAX_SCORE, saved.MaxScore__c, '배점 복사');
    Assert.isTrue(saved.IsRequired__c, '필수 복사');
    Assert.isTrue(saved.IsDeficient__c, '복사한 배점(5) 기준 2점은 미흡');
  }

  // 증명: 경계값 — 배점 5 × 0.6 = 3. 2점은 미흡, 3점은 정상
  @IsTest
  static void deficiencyBoundary_twoOfFiveIsDeficientThreeIsNot() {
    List<InspectionTemplateItem__c> templates = TestDataFactory.createTemplateItems(
      2,
      0,
      MAX_SCORE,
      true
    );
    Inspection__c ins = insertScheduledInspection();

    Test.startTest();
    insert TestDataFactory.createResults(
      ins,
      templates,
      new List<Decimal>{ 2, 3 },
      false
    );
    Test.stopTest();

    Map<Decimal, Boolean> deficientByScore = new Map<Decimal, Boolean>();
    for (InspectionResult__c result : getResults(ins.Id)) {
      deficientByScore.put(result.Score__c, result.IsDeficient__c);
    }
    Assert.isTrue(deficientByScore.get(2), '2 < 3 → 미흡');
    Assert.isFalse(deficientByScore.get(3), '3 = 3 → 정상(미만만 미흡)');
  }

  // 증명: 점수나 배점이 비면 판정 보류(미흡 아님) — 미흡으로 입력해 와도 false로 저장된다
  @IsTest
  static void missingScoreOrMaxScore_isNotDeficient() {
    Inspection__c ins = insertScheduledInspection();

    Test.startTest();
    insert new List<InspectionResult__c>{
      new InspectionResult__c(
        Inspection__c = ins.Id,
        ItemName__c = '점수 미입력',
        MaxScore__c = MAX_SCORE,
        IsDeficient__c = true
      ),
      new InspectionResult__c(
        Inspection__c = ins.Id,
        ItemName__c = '배점 없음',
        Score__c = 0,
        IsDeficient__c = true
      )
    };
    Test.stopTest();

    for (InspectionResult__c result : getResults(ins.Id)) {
      Assert.isFalse(
        result.IsDeficient__c,
        result.ItemName__c + ' → 판정 보류(false)'
      );
    }
  }

  // 증명: BR-11 — 템플릿의 항목명 · 배점 · 필수를 나중에 바꿔도 기존 결과의 스냅샷은 그대로이고,
  //       결과를 다시 저장하면 자기 스냅샷 배점으로 미흡을 다시 판정한다(update는 복사하지 않음)
  @IsTest
  static void templateChangedLater_existingResultKeepsSnapshot() {
    InspectionTemplateItem__c template = TestDataFactory.createTemplateItems(
      1,
      1,
      MAX_SCORE,
      true
    )[0];
    String originalName = template.Name;
    Inspection__c ins = insertScheduledInspection();
    insert TestDataFactory.createResults(
      ins,
      new List<InspectionTemplateItem__c>{ template },
      new List<Decimal>{ 4 },
      false
    );

    Test.startTest();
    template.Name = '바뀐 항목명';
    template.Category__c = '서비스';
    template.IsRequired__c = false;
    template.MaxScore__c = 10;
    update template;
    InspectionResult__c result = getOnlyResult(ins.Id);
    result.Score__c = 2;
    update result;
    Test.stopTest();

    InspectionResult__c saved = getOnlyResult(ins.Id);
    Assert.areEqual(originalName, saved.ItemName__c, '항목명은 당시 값');
    Assert.areEqual('위생', saved.Category__c, '분류는 당시 값');
    Assert.areEqual(MAX_SCORE, saved.MaxScore__c, '배점은 당시 값(5)');
    Assert.isTrue(saved.IsRequired__c, '필수는 당시 값');
    Assert.isTrue(
      saved.IsDeficient__c,
      '당시 배점 5 기준 2점은 미흡(바뀐 배점 10 기준이 아님)'
    );
  }

  // 증명: 템플릿 없는 insert(이관 · 테스트 데이터)는 입력한 스냅샷 그대로 저장되고 미흡만 판정된다
  @IsTest
  static void insertWithoutTemplate_keepsGivenSnapshot() {
    Inspection__c ins = insertScheduledInspection();

    Test.startTest();
    insert new InspectionResult__c(
      Inspection__c = ins.Id,
      ItemName__c = '이관 항목',
      Category__c = '서비스',
      MaxScore__c = 10,
      IsRequired__c = false,
      Score__c = 5
    );
    Test.stopTest();

    InspectionResult__c saved = getOnlyResult(ins.Id);
    Assert.areEqual('이관 항목', saved.ItemName__c, '입력한 항목명 유지');
    Assert.areEqual(10, saved.MaxScore__c, '입력한 배점 유지');
    Assert.isTrue(saved.IsDeficient__c, '5 < 10 × 0.6 → 미흡');
  }

  // 증명: 점수를 고쳐 저장하면 미흡을 다시 판정한다(미흡 → 정상)
  @IsTest
  static void updateScore_rejudgesDeficiency() {
    Inspection__c ins = insertScheduledInspection();
    insert TestDataFactory.createResults(
      ins,
      TestDataFactory.createTemplateItems(1, 0, MAX_SCORE, true),
      new List<Decimal>{ 1 },
      false
    );
    Assert.isTrue(getOnlyResult(ins.Id).IsDeficient__c, '전제: 1점은 미흡');

    Test.startTest();
    update new InspectionResult__c(Id = getOnlyResult(ins.Id).Id, Score__c = 5);
    Test.stopTest();

    Assert.isFalse(getOnlyResult(ins.Id).IsDeficient__c, '5점으로 고치면 정상');
  }

  // 증명: BR-03 — 20항목(100점) 중 위생 필수 1개만 미흡(2/5)이면 총점 97이어도 점검완료 시 불합격
  @IsTest
  static void requiredDeficientWithHighTotal_failsOnCompletion() {
    Inspection__c ins = insertScheduledInspection();
    insertTwentyItemResults(ins, 0);

    Test.startTest();
    ins.Status__c = TestDataFactory.STATUS_COMPLETED;
    update ins;
    Test.stopTest();

    Inspection__c saved = getInspection(ins.Id);
    Assert.areEqual(97, saved.ruTotalScore__c, '총점 97 / 100');
    Assert.areEqual(1, saved.ruDeficientRequiredCount__c, '필수 미흡 1개');
    Assert.areEqual(
      '불합격',
      saved.Judgement__c,
      '필수 미흡이면 총점과 무관하게 불합격'
    );
  }

  // 증명: 비필수 항목만 미흡(2/5)이면 감점만 되고 총점 97로 합격
  @IsTest
  static void nonRequiredDeficientOnly_passesOnCompletion() {
    Inspection__c ins = insertScheduledInspection();
    // NOTE: createTemplateItems는 앞 6개를 필수로 만든다 → 인덱스 6은 비필수
    insertTwentyItemResults(ins, 6);

    Test.startTest();
    ins.Status__c = TestDataFactory.STATUS_COMPLETED;
    update ins;
    Test.stopTest();

    Inspection__c saved = getInspection(ins.Id);
    Assert.areEqual(0, saved.ruDeficientRequiredCount__c, '필수 미흡 없음');
    Assert.areEqual('합격', saved.Judgement__c, '97 / 100 ≥ 합격선 0.8');
  }

  // 증명: 200건을 한 번에 insert해도 템플릿 조회는 SOQL 1번이고, 모두 복사 · 판정된다
  @IsTest
  static void bulk200_oneTemplateQueryAndAllJudged() {
    List<InspectionTemplateItem__c> templates = TestDataFactory.createTemplateItems(
      20,
      6,
      MAX_SCORE,
      true
    );
    List<Inspection__c> inspections = TestDataFactory.createInspections(
      TestDataFactory.createFranchises(10, true),
      1,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    );
    List<InspectionResult__c> results = new List<InspectionResult__c>();
    for (Inspection__c ins : inspections) {
      for (InspectionTemplateItem__c template : templates) {
        // NOTE: 스냅샷 없이 템플릿과 점수만 — 화면에서 새로 만들 때와 같다
        results.add(
          new InspectionResult__c(
            Inspection__c = ins.Id,
            TemplateItem__c = template.Id,
            Score__c = 2
          )
        );
      }
    }

    // NOTE: SOQL 횟수는 복제본으로 서비스만 따로 잰다 — insert는 Roll-Up 재계산으로 부모 트리거까지 돌아 조회가 섞인다.
    //       원본은 스냅샷이 빈 채로 insert해 트리거가 복사하는지 본다
    List<InspectionResult__c> probe = results.deepClone();

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    InspectionResultService.copyTemplateSnapshots(probe);
    Integer templateQueries = Limits.getQueries() - queriesBefore;
    insert results;
    Test.stopTest();

    Assert.areEqual(1, templateQueries, '200건이어도 템플릿 조회는 1번');
    Assert.areEqual(
      200,
      [
        SELECT COUNT()
        FROM InspectionResult__c
        WHERE
          MaxScore__c = :MAX_SCORE
          AND ItemName__c != NULL
          AND IsDeficient__c = TRUE
      ],
      '200건 모두 스냅샷 복사 + 미흡 판정'
    );
  }

  // 증명: 실제 입력자인 SV(템플릿 편집 권한 없음)가 자기 점검에 결과를 만들어도 스냅샷이 복사된다
  @IsTest
  static void svCreatesResult_snapshotCopied() {
    User sv = TestDataFactory.createSvUser('결과입력테스트SV', true);
    InspectionTemplateItem__c template = TestDataFactory.createTemplateItems(
      1,
      1,
      MAX_SCORE,
      true
    )[0];
    Inspection__c ins = TestDataFactory.createInspections(
      TestDataFactory.createFranchises(1, true),
      1,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      false
    )[0];
    ins.OwnerId = sv.Id;
    insert ins;

    Test.startTest();
    System.runAs(sv) {
      insert new InspectionResult__c(
        Inspection__c = ins.Id,
        TemplateItem__c = template.Id,
        Score__c = 3
      );
    }
    Test.stopTest();

    InspectionResult__c saved = getOnlyResult(ins.Id);
    Assert.areEqual(
      template.Name,
      saved.ItemName__c,
      'SV가 만들어도 항목명 복사'
    );
    Assert.areEqual(MAX_SCORE, saved.MaxScore__c, '배점 복사');
    Assert.isFalse(saved.IsDeficient__c, '3 / 5는 정상');
  }

  // 증명: 항목 미흡 기준이 비어 있으면 조용히 판정하지 않고 저장을 막는다
  @IsTest
  static void missingDeficiencyRate_blocksSave() {
    Inspection__c ins = insertScheduledInspection();
    InspectionRuleSelector.ruleOverride = new InspectionRule__mdt(
      PassRate__c = 0.8,
      CorrectionRate__c = 0.6,
      DeficiencyRate__c = null
    );

    Test.startTest();
    Database.SaveResult result = Database.insert(
      new InspectionResult__c(
        Inspection__c = ins.Id,
        ItemName__c = '기준 없음',
        MaxScore__c = MAX_SCORE,
        Score__c = 1
      ),
      false
    );
    Test.stopTest();

    Assert.isFalse(result.isSuccess(), '기준값이 없으면 저장하지 않는다');
    Assert.isTrue(
      result.getErrors()[0].getMessage().contains('DeficiencyRate__c'),
      '원인을 알려 준다: ' + result.getErrors()[0].getMessage()
    );
  }

  // ------------------------------------------------------------------ helpers

  private static Inspection__c insertScheduledInspection() {
    return TestDataFactory.createInspections(
      TestDataFactory.createFranchises(1, true),
      1,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    )[0];
  }

  // DESC: 새 점검표와 같은 구성(20항목 × 5점, 앞 6개 위생 필수). deficientIndex 항목만 2점, 나머지는 만점
  private static void insertTwentyItemResults(
    Inspection__c ins,
    Integer deficientIndex
  ) {
    List<InspectionTemplateItem__c> templates = TestDataFactory.createTemplateItems(
      20,
      6,
      MAX_SCORE,
      true
    );
    List<Decimal> scores = new List<Decimal>();
    for (Integer i = 0; i < templates.size(); i++) {
      scores.add(i == deficientIndex ? 2 : MAX_SCORE);
    }
    insert TestDataFactory.createResults(ins, templates, scores, false);
  }

  private static List<InspectionResult__c> getResults(Id inspectionId) {
    return [
      SELECT
        Id,
        ItemName__c,
        Category__c,
        MaxScore__c,
        IsRequired__c,
        Score__c,
        IsDeficient__c
      FROM InspectionResult__c
      WHERE Inspection__c = :inspectionId
    ];
  }

  private static InspectionResult__c getOnlyResult(Id inspectionId) {
    return getResults(inspectionId)[0];
  }

  private static Inspection__c getInspection(Id inspectionId) {
    return [
      SELECT ruTotalScore__c, ruDeficientRequiredCount__c, Judgement__c
      FROM Inspection__c
      WHERE Id = :inspectionId
    ];
  }
}
