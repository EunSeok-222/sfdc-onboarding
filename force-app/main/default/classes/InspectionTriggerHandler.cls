/* ======================================================================================
 * @description : 점검 트리거 핸들러. 이벤트별로 실행할 규칙을 정하고 oldMap 비교로 처리 대상만 추린다
 * @testClass   : InspectionTriggerHandlerTest
 * @layer       : TriggerHandler
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.11   Kai        Created     최초 작성 (뼈대)
 * ======================================================================================
 *  @see         : Inspection.trigger, InspectionService.cls, FranchiseInspectionDateService.cls
 * ======================================================================================*/
public with sharing class InspectionTriggerHandler {
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
    // TODO: 1) 상태 전이 검증 — 허용 표에 없는 이동이면 addError (같은 상태 재저장은 허용)
    // TODO: 2) 판정 세팅 — '점검완료'로 바뀐 점검 + 점검완료 상태에서 Roll-Up 값이 바뀐 점검만
  }

  /**
   * @description : 새 점검의 가맹점 최근 정기점검일을 다시 계산한다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param newInspections Trigger.new
   **/
  public void afterInsert(List<Inspection__c> newInspections) {
    // TODO: 가맹점 Id 수집 → FranchiseInspectionDateService 호출
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
    // TODO: 가맹점 · 점검일 · 레코드 유형이 바뀌었거나 상태가 '점검예정'과 다른 상태 사이에서 바뀐 점검만
    // TODO: 이전 가맹점(old)과 새 가맹점(new)을 둘 다 수집
  }

  /**
   * @description : 삭제된 점검의 가맹점 최근 정기점검일을 다시 계산한다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param oldInspections Trigger.old (delete에서는 Trigger.new가 null)
   **/
  public void afterDelete(List<Inspection__c> oldInspections) {
    // TODO: 가맹점 Id 수집 → FranchiseInspectionDateService 호출
  }

  /**
   * @description : 휴지통에서 복원된 점검의 가맹점 최근 정기점검일을 다시 계산한다.
   * @author      : 이은석(Kai) | 2026.10.11
   * @param newInspections Trigger.new
   **/
  public void afterUndelete(List<Inspection__c> newInspections) {
    // TODO: 가맹점 Id 수집 → FranchiseInspectionDateService 호출
  }
}
