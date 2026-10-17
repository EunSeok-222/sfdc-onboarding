/* ======================================================================================
 * @description : 회신(IF-004)이 전송실패인 출고 제한을 다시 보낸다 — 지정한 접수번호만, 물류 org(hankki-logistics) 전용
 * @layer       : Script
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 (D11 Step 7-B — 자동 재시도 대신 수동 재전송)
 * ======================================================================================
 *  실행 : sf apex run --file scripts/apex/supplyRestrictionResendResult.apex --target-org hankki-logistics
 *  NOTE : logistics/ 패키지 클래스를 쓴다 — kai-dev에서는 컴파일되지 않는다
 *  NOTE : 아래 requestNos에 적은 출고 제한만, 처리 상태가 반영완료 · 반영거절이고 회신 상태가 전송실패인 건만 다시 보낸다.
 *         전체 일괄 처리는 하지 않는다(목록이 비면 아무것도 안 함)
 *  NOTE : 레코드를 직접 바꾸지 않는다 — 회신 Queueable을 enqueue만 하고, 결과(전송완료 · 전송실패 + 회신 오류)는 Queueable이 기록한다.
 *         실행자 권한으로 보내므로 실행자에게 권한 집합 「점검 회신」이 필요하다. 10건이 넘으면 Queueable이 나눠 보낸다
 *  NOTE : 익명 실행에서는 SYSTEM_MODE를 쓸 수 없다 — 조회는 WITH USER_MODE(실행자에게 「출고 제한 관리」 필요)
 * ======================================================================================*/
List<String> requestNos = new List<String>{ 'SR-000001' };

List<Id> resendIds = new List<Id>();
Set<String> foundNos = new Set<String>();
if (!requestNos.isEmpty()) {
  for (SupplyRestriction__c restriction : [
    SELECT Id, Name, Status__c, CallbackStatus__c, CallbackError__c
    FROM SupplyRestriction__c
    WHERE Name IN :requestNos
    WITH USER_MODE
  ]) {
    foundNos.add(restriction.Name);
    if (
      restriction.CallbackStatus__c == SupplyRestrictionResultService.CALLBACK_FAILED &&
      SupplyRestrictionResultService.isResolved(restriction.Status__c)
    ) {
      System.debug(
        LoggingLevel.ERROR,
        '>>> ' + restriction.Name + ' · ' + restriction.Status__c + ' · 전송실패(' + restriction.CallbackError__c + ') → 다시 보냄'
      );
      resendIds.add(restriction.Id);
    } else {
      System.debug(
        LoggingLevel.ERROR,
        '>>> ' + restriction.Name + ' · ' + restriction.Status__c + ' · 회신 ' + restriction.CallbackStatus__c +
        ' — 전송실패가 아니거나 처리 전이라 그대로 둠'
      );
    }
  }
}
for (String requestNo : requestNos) {
  if (!foundNos.contains(requestNo)) {
    System.debug(LoggingLevel.ERROR, '>>> ' + requestNo + ' · 출고 제한 없음 — 그대로 둠');
  }
}
if (resendIds.isEmpty()) {
  System.debug(LoggingLevel.ERROR, '>>> 다시 보낼 건 없음');
} else {
  Id jobId = System.enqueueJob(new SupplyRestrictionResultQueueable(resendIds));
  System.debug(
    LoggingLevel.ERROR,
    '>>> 회신 job ' + jobId + ' · ' + resendIds.size() + '건 — 결과는 출고 제한의 회신 상태 · 회신 오류에서 확인'
  );
}
