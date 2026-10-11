/* ======================================================================================
 * @description : 가맹점 최근 정기점검일(LastRegularInspectionDate__c) 재계산
 * @testClass   : InspectionTriggerHandlerTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.11   Kai        Created     최초 작성 (뼈대)
 * ======================================================================================
 *  @see         : InspectionTriggerHandler.cls
 *  @note        : 집계 대상은 정기점검(RecordType Regular) 중 점검예정이 아닌 점검
 * ======================================================================================*/
// WARN: without sharing — 시스템이 관리하는 집계값. SV 재배치 후 이전 SV가 과거 점검을 삭제하면
//       더 이상 편집 권한이 없는 가맹점을 갱신해야 하므로 공유를 넘는다. 이 클래스에 다른 로직을 넣지 않는다.
public without sharing class FranchiseInspectionDateService {
  /**
   * @description : 가맹점별 최근 정기점검일을 남은 점검으로 다시 계산해 저장한다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param franchiseIds 다시 계산할 가맹점 Id 집합 (이전·새 가맹점 모두 포함)
   **/
  public static void recalculateLastRegularInspectionDates(
    Set<Id> franchiseIds
  ) {
    // TODO: 1) 대상 가맹점 전부 null로 미리 채움 (남은 정기점검이 없으면 집계 행이 안 나옴)
    // TODO: 2) MAX(InspectionDate__c) GROUP BY Franchise__c — SOQL 1번
    // TODO: 3) 대상 가맹점 update — DML 1번
  }
}
