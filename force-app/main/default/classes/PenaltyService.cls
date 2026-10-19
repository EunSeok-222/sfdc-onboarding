/* ======================================================================================
 * @description : 페널티 저장 전 규칙 — 공급 제한 기간 자동(BR-08 「1주」) · 같은 근거 점검 진행 중 페널티 중복 차단
 * @testClass   : PenaltyServiceTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — 기간 자동 · 중복 차단(리허설 3회차: 기간 역전으로 물류 400, 같은 점검에 공급 제한 2건)
 * ======================================================================================
 *  @see         : PenaltyTriggerHandler.cls, InspectionRuleSelector.cls, 검증 규칙 PeriodStartBeforeEnd
 *  @note        : 기간 역전(시작일 > 종료일)은 검증 규칙이 막고, 물류 통보 직전 LogisticsNotifyService.validate가 한 번 더 본다
 * ======================================================================================*/
public with sharing class PenaltyService {
  public static final String TYPE_SUPPLY_RESTRICTION = '공급 제한';
  public static final String STATUS_PENDING = '승인대기';
  public static final String STATUS_APPROVED = '승인';
  public static final String STATUS_REJECTED = '반려';

  // DESC: 진행 중 = 승인대기 · 승인. 반려는 끝난 건이라 같은 근거로 다시 발의할 수 있다
  private static final Set<String> ACTIVE_STATUSES = new Set<String>{
    STATUS_PENDING,
    STATUS_APPROVED
  };

  /**
   * @description : 공급 제한의 빈 시작일 · 종료일을 채운다 — 시작일 = 내일, 종료일 = 시작일 + (일수 - 1).
   *                입력한 값은 덮어쓰지 않는다(필드별). update는 승인대기 상태에서만 채운다.
   * @author      : 이은석(Kai) | 2026.10.19
   * @param penalties        Trigger.new (before — DML 없이 값만 바꾼다)
   * @param oldPenaltiesById Trigger.oldMap (insert면 null)
   **/
  public static void applyDefaultPeriods(
    List<Penalty__c> penalties,
    Map<Id, Penalty__c> oldPenaltiesById
  ) {
    List<Penalty__c> targets = new List<Penalty__c>();
    for (Penalty__c penalty : penalties) {
      // NOTE: 승인 · 반려 뒤에 기간을 채우면 승인한 내용 · 물류에 통보한 기간과 어긋난다 — update는 승인대기만
      Boolean isLockedStage =
        oldPenaltiesById != null &&
        penalty.Status__c != STATUS_PENDING;
      if (
        penalty.PenaltyType__c != TYPE_SUPPLY_RESTRICTION ||
        isLockedStage ||
        (penalty.StartDate__c != null &&
        penalty.EndDate__c != null)
      ) {
        continue;
      }
      targets.add(penalty);
    }
    if (targets.isEmpty()) {
      return; // NOTE: 대상이 없으면 기준값도 읽지 않는다
    }
    Integer days = InspectionRuleSelector.getSupplyRestrictionDays();
    Date tomorrow = Date.today().addDays(1);
    for (Penalty__c penalty : targets) {
      if (penalty.StartDate__c == null) {
        penalty.StartDate__c = tomorrow;
      }
      if (penalty.EndDate__c == null) {
        penalty.EndDate__c = penalty.StartDate__c.addDays(days - 1);
      }
    }
  }

  /**
   * @description : 같은 근거 점검 · 같은 유형으로 진행 중(승인대기 · 승인)인 페널티가 DB나 같은 저장 묶음에 있으면 막는다.
   *                근거 점검이 비었거나 반려 상태인 페널티는 검사하지 않는다. update는 근거 점검 · 유형이 바뀐 건만 본다.
   * @author      : 이은석(Kai) | 2026.10.19
   * @param penalties        Trigger.new
   * @param oldPenaltiesById Trigger.oldMap (insert면 null)
   **/
  public static void blockDuplicates(
    List<Penalty__c> penalties,
    Map<Id, Penalty__c> oldPenaltiesById
  ) {
    List<Penalty__c> targets = new List<Penalty__c>();
    Set<Id> sourceIds = new Set<Id>();
    Set<Id> selfIds = new Set<Id>();
    for (Penalty__c penalty : penalties) {
      if (
        penalty.SourceInspection__c == null ||
        penalty.Status__c == STATUS_REJECTED ||
        !isKeyChanged(penalty, oldPenaltiesById)
      ) {
        continue;
      }
      targets.add(penalty);
      sourceIds.add(penalty.SourceInspection__c);
      if (penalty.Id != null) {
        selfIds.add(penalty.Id);
      }
    }
    if (targets.isEmpty()) {
      return;
    }

    // PERF: SOQL 1번 — 근거 점검 · 유형 키 → 진행 중 페널티 번호
    Map<String, String> activeNosByKey = new DuplicateFinder()
      .findActiveNos(sourceIds, selfIds);
    Set<String> keysInBatch = new Set<String>();
    for (Penalty__c penalty : targets) {
      String key = keyOf(penalty.SourceInspection__c, penalty.PenaltyType__c);
      if (activeNosByKey.containsKey(key)) {
        penalty.addError(
          duplicateMessage(penalty.PenaltyType__c, activeNosByKey.get(key))
        );
      } else if (!keysInBatch.add(key)) {
        // DESC: 같은 저장 묶음(벌크 insert)에서 두 번째부터 막는다 — 아직 번호가 없어 문구로 알린다
        penalty.addError(
          duplicateMessage(penalty.PenaltyType__c, '같이 저장하는 다른 행')
        );
      }
    }
  }

  // DESC: insert는 항상 검사, update는 근거 점검 · 유형이 바뀐 경우만 — 상태 · 기간만 바뀐 재저장은 다시 보지 않는다
  private static Boolean isKeyChanged(
    Penalty__c penalty,
    Map<Id, Penalty__c> oldPenaltiesById
  ) {
    if (oldPenaltiesById == null) {
      return true;
    }
    Penalty__c oldPenalty = oldPenaltiesById.get(penalty.Id);
    return oldPenalty.SourceInspection__c != penalty.SourceInspection__c ||
      oldPenalty.PenaltyType__c != penalty.PenaltyType__c;
  }

  private static String keyOf(Id sourceInspectionId, String penaltyType) {
    return sourceInspectionId + '|' + penaltyType;
  }

  private static String duplicateMessage(String penaltyType, String existing) {
    return '이 점검을 근거로 진행 중인 ' +
      penaltyType +
      ' 페널티가 있습니다: ' +
      existing;
  }

  // NOTE: without sharing — 중복 판단은 저장하는 사용자가 볼 수 없는 페널티(OWD 비공개 · 다른 사람 소유)까지 봐야 한다.
  //       예) SV가 발의할 때 권역팀장 소유 진행 중 페널티가 있으면 막아야 한다. 돌려주는 것은 번호뿐이다
  // NOTE: 내부 클래스는 바깥 클래스의 sharing을 물려받지 않으므로 without sharing을 명시한다
  private without sharing class DuplicateFinder {
    public Map<String, String> findActiveNos(
      Set<Id> sourceIds,
      Set<Id> excludeIds
    ) {
      Map<String, String> activeNosByKey = new Map<String, String>();
      for (Penalty__c existing : [
        SELECT Name, SourceInspection__c, PenaltyType__c
        FROM Penalty__c
        WHERE
          SourceInspection__c IN :sourceIds
          AND Status__c IN :ACTIVE_STATUSES
          AND Id NOT IN :excludeIds
        WITH SYSTEM_MODE
        ORDER BY Name
      ]) {
        String key = keyOf(
          existing.SourceInspection__c,
          existing.PenaltyType__c
        );
        if (!activeNosByKey.containsKey(key)) {
          activeNosByKey.put(key, existing.Name);
        }
      }
      return activeNosByKey;
    }
  }
}
