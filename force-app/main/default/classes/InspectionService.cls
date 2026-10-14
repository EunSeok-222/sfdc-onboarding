/* ======================================================================================
 * @description : 점검 판정 일괄 계산과 가맹점별 점검 건수 집계 (D5 트리거 · D6 Batch · D7 LWC 공통 호출)
 * @testClass   : InspectionServiceTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.08   Kai        Created     최초 작성
 *  2026.10.11   Kai        Updated     트리거용 메모리 판정 메서드 applyJudgements 분리
 *  2026.10.13   Kai        Updated     판정 기준값 상수 제거 → InspectionRule__mdt(InspectionRuleSelector)에서 조회
 * ======================================================================================
 *  @see         : docs/ERD.md (R2 가맹점–점검 Lookup, 4장 Roll-Up), InspectionRuleSelector.cls
 *  @note        : 합격선 · 시정선(BR-02)은 Custom Metadata InspectionRule__mdt.Default에서 읽는다
 * ======================================================================================*/
public with sharing class InspectionService {
  /**
   * 점검 판정을 일괄 계산해 저장한다.
   * Roll-Up 필드만 사용하므로 결과 항목을 별도 조회하지 않는다.
   *
   * @param inspectionIds 판정 대상 점검 Id 집합
   */
  public static void judgeInspections(Set<Id> inspectionIds) {
    if (inspectionIds == null || inspectionIds.isEmpty()) {
      return;
    }

    List<Inspection__c> inspections = [
      // SOQL 1번
      SELECT Id, ruTotalScore__c, ruMaxScore__c, ruDeficientRequiredCount__c
      FROM Inspection__c
      WHERE Id IN :inspectionIds AND ruMaxScore__c > 0
    ];

    applyJudgements(inspections); // 메모리 계산

    update inspections; // DML 1번
  }

  /**
   * @description : 판정 필드를 메모리에서만 채운다. SOQL · DML이 없어 before 트리거에서 호출한다.
   *                배점 합계가 0인 점검(결과 항목 없음)은 판정을 바꾸지 않는다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param inspections Roll-Up 세 필드(총점 · 배점 합계 · 필수 미흡 수)가 들어 있는 점검
   **/
  public static void applyJudgements(List<Inspection__c> inspections) {
    if (inspections.isEmpty()) {
      return; // NOTE: 판정 대상이 없으면 기준값도 읽지 않는다 (트리거는 대상이 없어도 이 메서드를 부른다)
    }
    // PERF: 기준값은 루프 밖에서 1번만 읽는다
    InspectionRule__mdt rule = InspectionRuleSelector.getDefaultRule();
    for (Inspection__c ins : inspections) {
      if (ins.ruMaxScore__c == null || ins.ruMaxScore__c <= 0) {
        continue;
      }
      ins.Judgement__c = decideJudgement(ins, rule);
    }
  }

  /**
   * 가맹점별 점검 건수를 집계한다.
   * 가맹점–점검이 Lookup이라 Roll-Up Summary를 쓸 수 없어 Apex로 집계한다. (ERD R2)
   *
   * @param  franchiseIds 대상 가맹점 Id 집합
   * @return 가맹점 Id → 점검 건수
   */
  public static Map<Id, Integer> countInspectionsByFranchise(
    Set<Id> franchiseIds
  ) {
    Map<Id, Integer> inspectionCountsByFranchiseId = new Map<Id, Integer>();

    for (Id franchiseId : franchiseIds) {
      inspectionCountsByFranchiseId.put(franchiseId, 0); // 0건 가맹점 대비
    }

    for (AggregateResult ar : [
      SELECT Franchise__c franchiseId, COUNT(Id) cnt
      FROM Inspection__c
      WHERE Franchise__c IN :franchiseIds
      GROUP BY Franchise__c
    ]) {
      inspectionCountsByFranchiseId.put(
        (Id) ar.get('franchiseId'),
        (Integer) ar.get('cnt')
      );
    }
    return inspectionCountsByFranchiseId;
  }

  /**
   * 단일 점검의 판정값을 결정한다.
   * BR-03: 필수 항목 미흡이 있으면 점수와 무관하게 불합격.
   * BR-02: 득점률이 합격선 이상이면 합격, 시정선 이상이면 시정 필요, 그 아래는 불합격.
   */
  private static String decideJudgement(
    Inspection__c ins,
    InspectionRule__mdt rule
  ) {
    if (ins.ruDeficientRequiredCount__c > 0) {
      return '불합격';
    }
    Decimal rate = ins.ruTotalScore__c / ins.ruMaxScore__c;

    if (rate >= rule.PassRate__c)
      return '합격';
    if (rate >= rule.CorrectionRate__c)
      return '시정 필요';
    return '불합격';
  }
}
