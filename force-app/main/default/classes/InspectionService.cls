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
 *  2026.10.19   Kai        Updated     notifyConsecutiveFailures 추가 — 정기점검 불합격 2회 연속 감지 알림(BR-08 일부)
 * ======================================================================================
 *  @see         : docs/ERD.md (R2 가맹점–점검 Lookup, 4장 Roll-Up), InspectionRuleSelector.cls
 *  @note        : 합격선 · 시정선(BR-02)은 Custom Metadata InspectionRule__mdt.Default에서 읽는다
 * ======================================================================================*/
public with sharing class InspectionService {
  public static final String JUDGEMENT_FAIL = '불합격';
  private static final String SCHEDULED_STATUS = '점검예정';
  private static final Id REGULAR_RECORD_TYPE_ID = Schema.SObjectType.Inspection__c
    .getRecordTypeInfosByDeveloperName()
    .get('Regular')
    .getRecordTypeId();

  /**
   * @description : 정기점검의 판정이 불합격으로 "바뀐" 건마다, 같은 가맹점의 직전 정기점검(점검예정 제외, 점검일이 더 이른 것 중
   *                가장 최근)도 불합격이면 점검 소유자의 Manager에게 「점검 운영 알림」을 보낸다(대상 = 점검).
   *                이미 불합격인 점검을 다시 저장하면 판정이 바뀌지 않으므로 다시 보내지 않는다.
   *                SOQL은 건수와 무관하게 직전 점검 1번 + 수신자 1번(+ 알림 유형, 트랜잭션당 1번).
   * @author      : 이은석(Kai) | 2026.10.19
   * @param inspections        Trigger.new (after update — 판정은 before update에서 이미 정해졌다)
   * @param oldInspectionsById Trigger.oldMap
   **/
  public static void notifyConsecutiveFailures(
    List<Inspection__c> inspections,
    Map<Id, Inspection__c> oldInspectionsById
  ) {
    List<Inspection__c> targets = new List<Inspection__c>();
    Set<Id> franchiseIds = new Set<Id>();
    Date latestDate;
    for (Inspection__c ins : inspections) {
      if (
        ins.RecordTypeId != REGULAR_RECORD_TYPE_ID ||
        ins.Judgement__c != JUDGEMENT_FAIL ||
        oldInspectionsById.get(ins.Id).Judgement__c == JUDGEMENT_FAIL ||
        ins.InspectionDate__c == null
      ) {
        continue;
      }
      targets.add(ins);
      franchiseIds.add(ins.Franchise__c);
      latestDate = latestDate == null ||
        ins.InspectionDate__c > latestDate
        ? ins.InspectionDate__c
        : latestDate;
    }
    if (targets.isEmpty()) {
      return;
    }

    // DESC: 같은 가맹점의 정기점검 이력(점검예정 제외)을 최근 순으로 1번에 — 대상마다 「자기보다 이른 첫 건」이 직전 점검
    // NOTE: SYSTEM_MODE — 직전 점검을 다른 SV가 했어도(소유자가 달라도) 연속 여부는 판단해야 한다
    Map<Id, List<Inspection__c>> historyByFranchiseId = new Map<Id, List<Inspection__c>>();
    for (Inspection__c previous : [
      SELECT
        Id,
        Name,
        Franchise__c,
        Franchise__r.Name,
        InspectionDate__c,
        Judgement__c
      FROM Inspection__c
      WHERE
        Franchise__c IN :franchiseIds
        AND RecordTypeId = :REGULAR_RECORD_TYPE_ID
        AND Status__c != :SCHEDULED_STATUS
        AND InspectionDate__c < :latestDate
        AND Id NOT IN :targets
      WITH SYSTEM_MODE
      ORDER BY InspectionDate__c DESC, CreatedDate DESC
    ]) {
      if (!historyByFranchiseId.containsKey(previous.Franchise__c)) {
        historyByFranchiseId.put(
          previous.Franchise__c,
          new List<Inspection__c>()
        );
      }
      historyByFranchiseId.get(previous.Franchise__c).add(previous);
    }

    Map<Id, Inspection__c> previousFailsByTargetId = new Map<Id, Inspection__c>();
    Set<Id> ownerIds = new Set<Id>();
    for (Inspection__c target : targets) {
      Inspection__c previous = findPrevious(
        historyByFranchiseId.get(target.Franchise__c),
        target.InspectionDate__c
      );
      if (previous != null && previous.Judgement__c == JUDGEMENT_FAIL) {
        previousFailsByTargetId.put(target.Id, previous);
        ownerIds.add(target.OwnerId);
      }
    }
    if (previousFailsByTargetId.isEmpty()) {
      return;
    }

    Map<Id, Id> recipientsByOwnerId = OperationAlertService.resolveManagerRecipients(
      ownerIds
    );
    List<OperationAlertService.Alert> alerts = new List<OperationAlertService.Alert>();
    for (Inspection__c target : targets) {
      Inspection__c previous = previousFailsByTargetId.get(target.Id);
      Id recipientId = recipientsByOwnerId.get(target.OwnerId);
      if (previous == null || recipientId == null) {
        continue; // NOTE: 직전도 불합격이 아니거나, 큐 소유(미배정) · 비활성 소유자라 받을 사람이 없다
      }
      alerts.add(
        new OperationAlertService.Alert(
          target.Id,
          '정기점검 불합격 2회 연속 — ' + previous.Franchise__r.Name,
          target.Name +
            ' 불합격, 직전 정기점검 ' +
            previous.Name +
            '(' +
            previous.InspectionDate__c.format() +
            ')도 불합격입니다. 공급 제한 검토(BR-08)',
          new Set<String>{ recipientId }
        )
      );
    }
    OperationAlertService.send(alerts);
  }

  // DESC: 최근 순 이력에서 기준일보다 이른 첫 건 = 직전 점검
  private static Inspection__c findPrevious(
    List<Inspection__c> history,
    Date beforeDate
  ) {
    if (history == null) {
      return null;
    }
    for (Inspection__c previous : history) {
      if (previous.InspectionDate__c < beforeDate) {
        return previous;
      }
    }
    return null;
  }

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
