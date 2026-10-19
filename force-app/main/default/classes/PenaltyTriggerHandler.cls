/* ======================================================================================
 * @description : 페널티 트리거 핸들러. oldMap 비교로 처리 대상만 추려 물류 통보 요청(로그 · 이벤트)을 남긴다
 * @testClass   : PenaltyTriggerHandlerTest
 * @layer       : TriggerHandler
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.16   Kai        Created     최초 작성 — 공급 제한 승인 시 물류 통보 요청 (BR-08, IF-001)
 *  2026.10.19   Kai        Updated     before insert · update 분기 추가 — PenaltyService 중복 차단 · 공급 제한 기간 자동
 * ======================================================================================
 *  @see         : Penalty.trigger, LogisticsNotifyService.cls, PenaltyService.cls
 *  @note        : 승인 트랜잭션(승인자 권한)에서는 콜아웃 · 페널티 수정 · enqueue를 하지 않는다 — 로그와 이벤트만 남긴다
 * ======================================================================================*/
public with sharing class PenaltyTriggerHandler {
  /**
   * @description : before insert — 중복이면 막고, 공급 제한의 빈 기간을 채운다.
   * @author      : 이은석(Kai) | 2026.10.19
   * @param newPenalties Trigger.new
   **/
  public void beforeInsert(List<Penalty__c> newPenalties) {
    PenaltyService.blockDuplicates(newPenalties, null);
    PenaltyService.applyDefaultPeriods(newPenalties, null);
  }

  /**
   * @description : before update — 근거 점검 · 유형이 바뀐 건만 중복 검사, 승인대기 공급 제한만 빈 기간을 채운다.
   * @author      : 이은석(Kai) | 2026.10.19
   * @param newPenalties     Trigger.new
   * @param oldPenaltiesById Trigger.oldMap
   **/
  public void beforeUpdate(
    List<Penalty__c> newPenalties,
    Map<Id, Penalty__c> oldPenaltiesById
  ) {
    PenaltyService.blockDuplicates(newPenalties, oldPenaltiesById);
    PenaltyService.applyDefaultPeriods(newPenalties, oldPenaltiesById);
  }

  /**
   * @description : after update — 공급 제한이 「승인」으로 바뀐 페널티만 물류 통보 요청을 남긴다.
   * @author      : 이은석(Kai) | 2026.10.16
   * @param newPenalties       Trigger.new
   * @param oldPenaltiesById   Trigger.oldMap
   **/
  public void afterUpdate(
    List<Penalty__c> newPenalties,
    Map<Id, Penalty__c> oldPenaltiesById
  ) {
    requestLogisticsNotifications(newPenalties, oldPenaltiesById);
  }

  // DESC: 상태가 「승인」으로 "바뀐" 건만 고른다 — 이미 승인인 건의 재저장은 다시 요청하지 않는다
  private void requestLogisticsNotifications(
    List<Penalty__c> newPenalties,
    Map<Id, Penalty__c> oldPenaltiesById
  ) {
    List<Penalty__c> targets = new List<Penalty__c>();
    for (Penalty__c penalty : newPenalties) {
      Penalty__c oldPenalty = oldPenaltiesById.get(penalty.Id);
      if (
        penalty.PenaltyType__c ==
        LogisticsNotifyService.PENALTY_TYPE_SUPPLY_RESTRICTION &&
        penalty.Status__c == LogisticsNotifyService.PENALTY_STATUS_APPROVED &&
        oldPenalty.Status__c != LogisticsNotifyService.PENALTY_STATUS_APPROVED
      ) {
        targets.add(penalty);
      }
    }
    // PERF: 200건이 한 번에 승인돼도 로그 insert 1번 · 이벤트 1건
    LogisticsNotifyService.requestNotifications(targets);
  }
}
