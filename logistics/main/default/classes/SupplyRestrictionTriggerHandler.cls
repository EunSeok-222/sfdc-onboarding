/* ======================================================================================
 * @description : 출고 제한 트리거 핸들러. oldMap 비교로 「접수 → 반영완료 · 반영거절」 처리 건만 추려 회신(IF-004)을 준비한다
 * @testClass   : SupplyRestrictionResultQueueableTest
 * @layer       : TriggerHandler
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 처리 일시 세팅 · 회신 Queueable enqueue 1번(Step 7-B)
 * ======================================================================================
 *  @see         : SupplyRestriction.trigger, SupplyRestrictionResultService.cls, SupplyRestrictionResultQueueable.cls
 *  @note        : 가상 물류 시스템(hankki-logistics org) 소스다. 상태를 바꾼 트랜잭션에서는 콜아웃하지 않는다 —
 *                 Queueable이 커밋 뒤에 상태를 바꾼 사용자 권한으로 보낸다
 * ======================================================================================*/
public with sharing class SupplyRestrictionTriggerHandler {
  /**
   * @description : before update — 처리된 건의 처리 일시(비어 있을 때) · 회신 상태를 세팅한다.
   * @author      : 이은석(Kai) | 2026.10.18
   * @param newRestrictions      Trigger.new
   * @param oldRestrictionsById  Trigger.oldMap
   **/
  public void beforeUpdate(
    List<SupplyRestriction__c> newRestrictions,
    Map<Id, SupplyRestriction__c> oldRestrictionsById
  ) {
    SupplyRestrictionResultService.prepareCallbacks(
      findResolved(newRestrictions, oldRestrictionsById)
    );
  }

  /**
   * @description : after update — 처리된 건을 모아 회신 Queueable을 1번만 enqueue한다.
   * @author      : 이은석(Kai) | 2026.10.18
   * @param newRestrictions      Trigger.new
   * @param oldRestrictionsById  Trigger.oldMap
   **/
  public void afterUpdate(
    List<SupplyRestriction__c> newRestrictions,
    Map<Id, SupplyRestriction__c> oldRestrictionsById
  ) {
    List<Id> restrictionIds = new List<Id>();
    for (
      SupplyRestriction__c restriction : findResolved(
        newRestrictions,
        oldRestrictionsById
      )
    ) {
      restrictionIds.add(restriction.Id);
    }
    // PERF: 200건이 한 번에 처리돼도 job은 1개 — Queueable이 10건씩 보내고 남은 건을 다음 job으로 넘긴다
    if (!restrictionIds.isEmpty()) {
      System.enqueueJob(new SupplyRestrictionResultQueueable(restrictionIds));
    }
  }

  // DESC: 상태가 「접수」에서 반영완료 · 반영거절로 "바뀐" 건만 고른다 — 재저장 · 결과 기록(Queueable의 update)은 다시 보내지 않는다
  private List<SupplyRestriction__c> findResolved(
    List<SupplyRestriction__c> newRestrictions,
    Map<Id, SupplyRestriction__c> oldRestrictionsById
  ) {
    List<SupplyRestriction__c> resolved = new List<SupplyRestriction__c>();
    for (SupplyRestriction__c restriction : newRestrictions) {
      if (
        oldRestrictionsById.get(restriction.Id).Status__c ==
        SupplyRestrictionService.STATUS_RECEIVED &&
        SupplyRestrictionResultService.isResolved(restriction.Status__c)
      ) {
        resolved.add(restriction);
      }
    }
    return resolved;
  }
}
