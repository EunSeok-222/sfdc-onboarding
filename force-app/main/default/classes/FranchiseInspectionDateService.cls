/* ======================================================================================
 * @description : 가맹점 최근 정기점검일(LastRegularInspectionDate__c) 재계산
 * @testClass   : InspectionTriggerHandlerTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.11   Kai        Created     최초 작성 (뼈대)
 *  2026.10.11   Kai        Updated     최근 정기점검일 재계산 구현
 * ======================================================================================
 *  @see         : InspectionTriggerHandler.cls
 *  @note        : 집계 대상은 정기점검(RecordType Regular) 중 점검예정이 아닌 점검
 * ======================================================================================*/
// WARN: without sharing — 시스템이 관리하는 집계값. SV 재배치 후 이전 SV가 과거 점검을 삭제하면
//       더 이상 편집 권한이 없는 가맹점을 갱신해야 하므로 공유를 넘는다. 이 클래스에 다른 로직을 넣지 않는다.
public without sharing class FranchiseInspectionDateService {
  public static final String REGULAR_RECORD_TYPE = 'Regular';
  public static final String SCHEDULED_STATUS = '점검예정';

  /**
   * @description : 가맹점별 최근 정기점검일을 남은 점검으로 다시 계산해 저장한다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param franchiseIds 다시 계산할 가맹점 Id 집합 (이전·새 가맹점 모두 포함)
   **/
  public static void recalculateLastRegularInspectionDates(
    Set<Id> franchiseIds
  ) {
    Set<Id> targetIds = new Set<Id>(franchiseIds);
    targetIds.remove(null);
    if (targetIds.isEmpty()) {
      return;
    }

    // DESC: 1) 대상 가맹점을 전부 null로 미리 채움 — 남은 정기점검이 없는 가맹점은 집계 행이 나오지 않아 옛 날짜가 남는 것을 방지
    Map<Id, Account> franchisesById = new Map<Id, Account>();
    for (Id franchiseId : targetIds) {
      franchisesById.put(
        franchiseId,
        new Account(Id = franchiseId, LastRegularInspectionDate__c = null)
      );
    }

    // DESC: 2) 남은 정기점검의 최근 점검일 — SOQL 1번 (after delete 시점에는 삭제된 점검이 이미 빠져 있음)
    for (AggregateResult ar : [
      SELECT Franchise__c franchiseId, MAX(InspectionDate__c) lastDate
      FROM Inspection__c
      WHERE
        Franchise__c IN :targetIds
        AND RecordType.DeveloperName = :REGULAR_RECORD_TYPE
        AND Status__c != :SCHEDULED_STATUS
      GROUP BY Franchise__c
    ]) {
      franchisesById.get((Id) ar.get('franchiseId'))
        .LastRegularInspectionDate__c = (Date) ar.get('lastDate');
    }

    // DESC: 3) 대상 가맹점 일괄 저장 — DML 1번
    // WARN: 가맹점 Duplicate Rule(수정 시 Block)이 이 update에도 적용된다. 사업자번호가 중복된 가맹점이 생기면 점검 저장이 실패함
    update franchisesById.values();
  }
}
