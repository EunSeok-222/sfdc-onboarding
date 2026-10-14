/* ======================================================================================
 * @description : 점검 기준(InspectionRule__mdt) 외부화를 검증하는 테스트 클래스
 * @testTarget  : InspectionRuleSelector, InspectionService, 시정조치 기한 자동설정 Flow
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.13   Kai        Created     최초 작성
 * ======================================================================================
 *  @note        : Custom Metadata는 SeeAllData와 무관하게 테스트에서도 배포된 레코드가 보인다.
 *                 Apex 쪽은 ruleOverride로 값을 바꿀 수 있지만, Flow는 항상 배포된 레코드를 읽는다
 * ======================================================================================*/
@IsTest
private class InspectionRuleSelectorTest {
  // 배포된 Default 기준이 존재하고 값이 정책 범위 안에 있다
  @IsTest
  static void defaultRule_deployed_isValid() {
    InspectionRule__mdt rule = InspectionRuleSelector.getDefaultRule();

    Assert.isNotNull(rule, '점검 기준 Default 레코드가 배포되어 있어야 한다');
    Assert.isTrue(
      rule.CorrectionRate__c <= rule.PassRate__c && rule.PassRate__c <= 1,
      '시정선은 합격선 이하, 합격선은 1 이하여야 한다. 실제: 합격선 ' +
        rule.PassRate__c +
        ' / 시정선 ' +
        rule.CorrectionRate__c
    );
  }

  // 코드는 그대로 두고 기준값만 0.9로 올리면 80점 판정이 합격 → 시정 필요로 바뀐다
  @IsTest
  static void passRateRaised_changesJudgement() {
    InspectionRuleSelector.ruleOverride = new InspectionRule__mdt(
      PassRate__c = 0.9,
      CorrectionRate__c = 0.6
    );
    Inspection__c ins = newScoredInspection(80, 100, 0);

    InspectionService.applyJudgements(new List<Inspection__c>{ ins });

    Assert.areEqual(
      '시정 필요',
      ins.Judgement__c,
      '합격선을 0.9로 올리면 득점률 0.8은 시정 필요여야 한다 — 기준값이 코드 밖에 있다는 증거'
    );
  }

  // 시정조치 기한을 비워 두면 Flow가 Custom Metadata의 일수로 채운다 (위생 / 그 외)
  @IsTest
  static void dueDays_fromRule_appliedByFlow() {
    InspectionRule__mdt rule = InspectionRuleSelector.getDefaultRule();
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    Inspection__c ins = TestDataFactory.createInspections(
      new List<Account>{ franchise },
      1,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    )[0];
    // NOTE: 템플릿 2개 중 앞 1개가 필수 → 분류 '위생', 나머지는 '서비스'
    List<InspectionTemplateItem__c> items = TestDataFactory.createTemplateItems(
      2,
      1,
      10,
      true
    );
    List<InspectionResult__c> results = TestDataFactory.createResults(
      ins,
      items,
      new List<Decimal>{ 5, 5 },
      true
    );

    Test.startTest();
    TestDataFactory.createCorrectiveActions(
      results,
      1,
      CorrectiveActionService.STATUS_REQUESTED,
      null,
      true
    );
    Test.stopTest();

    Map<Id, Date> dueDatesByResultId = new Map<Id, Date>();
    for (CorrectiveAction__c action : [
      SELECT InspectionResult__c, DueDate__c
      FROM CorrectiveAction__c
    ]) {
      dueDatesByResultId.put(action.InspectionResult__c, action.DueDate__c);
    }
    Assert.areEqual(
      Date.today().addDays(rule.SanitationDueDays__c.intValue()),
      dueDatesByResultId.get(results[0].Id),
      '위생 항목 시정조치 기한은 오늘 + 위생 시정 기한(일)이어야 한다'
    );
    Assert.areEqual(
      Date.today().addDays(rule.DefaultDueDays__c.intValue()),
      dueDatesByResultId.get(results[1].Id),
      '위생 외 항목 시정조치 기한은 오늘 + 일반 시정 기한(일)이어야 한다'
    );
  }

  // DESC: Roll-Up은 생성자로 대입 불가 — JSON 역직렬화로 주입 (InspectionServiceTest와 같은 방식)
  private static Inspection__c newScoredInspection(
    Decimal totalScore,
    Decimal maxScore,
    Decimal deficientRequiredCount
  ) {
    return (Inspection__c) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{
          'ruTotalScore__c' => totalScore,
          'ruMaxScore__c' => maxScore,
          'ruDeficientRequiredCount__c' => deficientRequiredCount
        }
      ),
      Inspection__c.class
    );
  }
}
