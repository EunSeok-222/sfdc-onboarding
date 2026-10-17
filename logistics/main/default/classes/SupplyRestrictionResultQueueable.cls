/* ======================================================================================
 * @description : 처리된 출고 제한의 결과를 kai-dev에 회신하는 Queueable (IF-004 송신) — 10건씩, 남으면 다음 job
 * @testClass   : SupplyRestrictionResultQueueableTest
 * @layer       : Queueable
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 10건씩 전송 위임 · 남은 건 다음 job 체인(Step 7-B)
 * ======================================================================================
 *  @see         : SupplyRestrictionTriggerHandler.cls, SupplyRestrictionResultService.cls
 *  @note        : 가상 물류 시스템(hankki-logistics org) 소스다. enqueue한 사용자(상태를 바꾼 사람) 권한으로 실행된다 —
 *                 그 사용자에게 권한 집합 「점검 회신」이 없으면 콜아웃이 실패하고 전송실패로 기록된다
 * ======================================================================================*/
public with sharing class SupplyRestrictionResultQueueable implements Queueable, Database.AllowsCallouts {
  private final List<Id> restrictionIds;

  // DESC: 테스트에서 체인 대신 다음 job에 넘길 Id를 남겨 Assert한다(아래 enqueueNext 참고)
  @TestVisible
  private static List<Id> chainedIdsInTest;

  public SupplyRestrictionResultQueueable(List<Id> restrictionIds) {
    this.restrictionIds = restrictionIds;
  }

  public void execute(QueueableContext context) {
    List<Id> currentIds = new List<Id>();
    List<Id> remainingIds = new List<Id>();
    for (Id restrictionId : restrictionIds) {
      if (currentIds.size() < SupplyRestrictionResultService.BATCH_SIZE) {
        currentIds.add(restrictionId);
      } else {
        remainingIds.add(restrictionId);
      }
    }
    SupplyRestrictionResultService.sendResults(currentIds);
    if (!remainingIds.isEmpty()) {
      enqueueNext(remainingIds);
    }
  }

  // NOTE: Apex 테스트에서는 실행 중인 Queueable 안에서 다음 job을 체인하면 오류가 난다(플랫폼 제약).
  //       테스트일 때만 체인 대신 넘길 Id를 기록한다 — 운영 동작은 그대로다
  private static void enqueueNext(List<Id> remainingIds) {
    if (Test.isRunningTest() && System.isQueueable()) {
      chainedIdsInTest = remainingIds;
      return;
    }
    System.enqueueJob(new SupplyRestrictionResultQueueable(remainingIds));
  }
}
