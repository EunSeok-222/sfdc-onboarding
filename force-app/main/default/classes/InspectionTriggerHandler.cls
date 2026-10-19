/* ======================================================================================
 * @description : 점검 트리거 핸들러. 이벤트별로 실행할 규칙을 정하고 oldMap 비교로 처리 대상만 추린다
 * @testClass   : InspectionTriggerHandlerTest
 * @layer       : TriggerHandler
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.11   Kai        Created     최초 작성 (뼈대)
 *  2026.10.11   Kai        Updated     상태 전이 검증 · 판정 세팅 · 최근 정기점검일 재계산 연결
 *  2026.10.18   Kai        Updated     after insert — 새 정기점검(이관번호 없음 · 점검예정)에 결과 항목 자동 생성 연결(D11)
 *  2026.10.19   Kai        Updated     after update — 정기점검 불합격 2회 연속 알림 연결(InspectionService.notifyConsecutiveFailures)
 * ======================================================================================
 *  @see         : Inspection.trigger, InspectionService.cls, InspectionResultService.cls, FranchiseInspectionDateService.cls
 * ======================================================================================*/
public with sharing class InspectionTriggerHandler {
  // DESC: 상태 전이 허용 표 — 키 = 현재 상태, 값 = 갈 수 있는 다음 상태
  // NOTE: 페널티 진행은 페널티 레코드의 승인 상태가 담당하므로 점검 상태에는 '페널티승인대기'를 두지 않는다
  private static final Map<String, Set<String>> ALLOWED_NEXT_STATUSES_BY_STATUS = new Map<String, Set<String>>{
    '점검예정' => new Set<String>{ '점검완료' },
    '점검완료' => new Set<String>{ '시정중', '종료' },
    '시정중' => new Set<String>{ '지연', '재점검완료' },
    '지연' => new Set<String>{ '재점검완료' },
    '재점검완료' => new Set<String>{ '종료' },
    '종료' => new Set<String>()
  };

  private static final String COMPLETED_STATUS = '점검완료';

  // NOTE: 레코드 유형 Id는 org마다 다르므로 DeveloperName으로 찾는다 (describe라 SOQL 소모 없음)
  private static final Id REGULAR_RECORD_TYPE_ID = Schema.SObjectType.Inspection__c
    .getRecordTypeInfosByDeveloperName()
    .get(FranchiseInspectionDateService.REGULAR_RECORD_TYPE)
    .getRecordTypeId();

  /**
   * @description : 저장 직전 같은 레코드를 검증·세팅한다. DML 없이 newInspections를 직접 수정한다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param newInspections     Trigger.new
   * @param oldInspectionsById Trigger.oldMap
   **/
  public void beforeUpdate(
    List<Inspection__c> newInspections,
    Map<Id, Inspection__c> oldInspectionsById
  ) {
    validateStatusTransitions(newInspections, oldInspectionsById);
    applyJudgementsOnCompletion(newInspections, oldInspectionsById);
  }

  /**
   * @description : 새 점검의 가맹점 최근 정기점검일을 다시 계산한다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param newInspections Trigger.new
   **/
  public void afterInsert(List<Inspection__c> newInspections) {
    recalculateFranchiseDates(collectCountedFranchiseIds(newInspections));
    InspectionResultService.createPendingResults(
      collectNewRegularInspections(newInspections)
    );
  }

  // DESC: 결과 항목 자동 생성 대상 — 정기점검이고, 이관번호가 없고(이관 · 테스트 · 데모 데이터 제외), 점검예정인 것만.
  //       불시점검 · 재점검은 2차. 점검완료로 바로 들어온 점검에 빈 20행을 붙이면 0 / 100으로 즉시 불합격이 되므로 제외
  // NOTE: 재귀 없음 — 결과 insert는 점검을 다시 insert하지 않고, 그 뒤 Roll-Up 갱신(점검 update)은 점수가 없어 판정 · 날짜 재계산을 건너뛴다
  private List<Inspection__c> collectNewRegularInspections(
    List<Inspection__c> inspections
  ) {
    List<Inspection__c> targets = new List<Inspection__c>();
    for (Inspection__c ins : inspections) {
      if (
        ins.RecordTypeId == REGULAR_RECORD_TYPE_ID &&
        String.isBlank(ins.InspectionNo__c) &&
        ins.Status__c == FranchiseInspectionDateService.SCHEDULED_STATUS
      ) {
        targets.add(ins);
      }
    }
    return targets;
  }

  /**
   * @description : 최근 정기점검일에 영향을 주는 변경이 있으면 이전·새 가맹점을 모두 다시 계산한다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param newInspections     Trigger.new
   * @param oldInspectionsById Trigger.oldMap
   **/
  public void afterUpdate(
    List<Inspection__c> newInspections,
    Map<Id, Inspection__c> oldInspectionsById
  ) {
    Set<Id> franchiseIds = new Set<Id>();
    for (Inspection__c ins : newInspections) {
      Inspection__c oldIns = oldInspectionsById.get(ins.Id);
      Boolean wasCounted = isCountedRegularInspection(oldIns);
      Boolean isCounted = isCountedRegularInspection(ins);

      // DESC: 집계 대상 여부가 바뀌었거나, 대상인 점검의 가맹점 · 점검일이 바뀐 경우만 다시 계산 (점수 · 판정 수정은 건너뜀)
      Boolean affectsDate =
        wasCounted != isCounted ||
        (isCounted &&
        (ins.Franchise__c != oldIns.Franchise__c ||
        ins.InspectionDate__c != oldIns.InspectionDate__c));

      if (affectsDate) {
        // NOTE: 가맹점이 A → B로 바뀌면 A는 점검이 빠지고 B는 들어오므로 둘 다 다시 계산
        franchiseIds.add(oldIns.Franchise__c);
        franchiseIds.add(ins.Franchise__c);
      }
    }
    recalculateFranchiseDates(franchiseIds);
    InspectionService.notifyConsecutiveFailures(
      newInspections,
      oldInspectionsById
    );
  }

  /**
   * @description : 삭제된 점검의 가맹점 최근 정기점검일을 다시 계산한다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param oldInspections Trigger.old (delete에서는 Trigger.new가 null)
   **/
  public void afterDelete(List<Inspection__c> oldInspections) {
    recalculateFranchiseDates(collectCountedFranchiseIds(oldInspections));
  }

  /**
   * @description : 휴지통에서 복원된 점검의 가맹점 최근 정기점검일을 다시 계산한다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param newInspections Trigger.new
   **/
  public void afterUndelete(List<Inspection__c> newInspections) {
    recalculateFranchiseDates(collectCountedFranchiseIds(newInspections));
  }

  /**
   * @description : 판정을 계산할 점검만 골라 InspectionService.applyJudgements에 넘긴다.
   *                '점검완료'로 바뀐 점검, 그리고 이미 점검완료인데 점수(Roll-Up)가 바뀐 점검이 대상이다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param newInspections     Trigger.new
   * @param oldInspectionsById Trigger.oldMap
   **/
  private void applyJudgementsOnCompletion(
    List<Inspection__c> newInspections,
    Map<Id, Inspection__c> oldInspectionsById
  ) {
    List<Inspection__c> targets = new List<Inspection__c>();
    for (Inspection__c ins : newInspections) {
      if (ins.Status__c != COMPLETED_STATUS) {
        continue; // NOTE: 시정중 이후 단계는 판정 고정. 이후 점수 수정은 Field History로 추적
      }
      Inspection__c oldIns = oldInspectionsById.get(ins.Id);
      Boolean becameCompleted = oldIns.Status__c != COMPLETED_STATUS;
      Boolean scoreChanged =
        ins.ruTotalScore__c != oldIns.ruTotalScore__c ||
        ins.ruMaxScore__c != oldIns.ruMaxScore__c ||
        ins.ruDeficientRequiredCount__c != oldIns.ruDeficientRequiredCount__c;

      if (becameCompleted || scoreChanged) {
        targets.add(ins);
      }
    }
    // NOTE: Trigger.new를 그대로 수정하므로 SOQL · DML 없음
    InspectionService.applyJudgements(targets);
  }

  /**
   * @description : 최근 정기점검일 집계 대상(정기점검이면서 점검예정이 아닌 점검)의 가맹점 Id를 모은다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param inspections 점검 목록
   * @return Set<Id> 가맹점 Id
   **/
  private Set<Id> collectCountedFranchiseIds(List<Inspection__c> inspections) {
    Set<Id> franchiseIds = new Set<Id>();
    for (Inspection__c ins : inspections) {
      if (isCountedRegularInspection(ins)) {
        franchiseIds.add(ins.Franchise__c);
      }
    }
    return franchiseIds;
  }

  private Boolean isCountedRegularInspection(Inspection__c ins) {
    return ins.RecordTypeId == REGULAR_RECORD_TYPE_ID &&
      ins.Status__c != FranchiseInspectionDateService.SCHEDULED_STATUS;
  }

  private void recalculateFranchiseDates(Set<Id> franchiseIds) {
    if (!franchiseIds.isEmpty()) {
      FranchiseInspectionDateService.recalculateLastRegularInspectionDates(
        franchiseIds
      );
    }
  }

  /**
   * @description : 허용 표에 없는 상태 이동이면 상태 필드에 오류를 걸어 저장을 막는다.
   *                상태가 바뀌지 않은 저장은 검사하지 않는다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param newInspections     Trigger.new
   * @param oldInspectionsById Trigger.oldMap
   **/
  private void validateStatusTransitions(
    List<Inspection__c> newInspections,
    Map<Id, Inspection__c> oldInspectionsById
  ) {
    for (Inspection__c ins : newInspections) {
      String oldStatus = oldInspectionsById.get(ins.Id).Status__c;
      String newStatus = ins.Status__c;

      if (oldStatus == newStatus) {
        continue;
      }

      // WARN: 표에 없는 상태(빈 값 · 비활성 값)에서 출발하면 get()이 null — null 체크 없이 contains()를 부르면 NullPointerException
      Set<String> allowedNextStatuses = ALLOWED_NEXT_STATUSES_BY_STATUS.get(
        oldStatus
      );
      if (
        allowedNextStatuses == null || !allowedNextStatuses.contains(newStatus)
      ) {
        ins.Status__c.addError(
          '\'' +
            oldStatus +
            '\'에서 \'' +
            newStatus +
            '\'(으)로 바꿀 수 없습니다.'
        );
      }
    }
  }
}
