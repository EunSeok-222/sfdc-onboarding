/* ======================================================================================
 * @description : 실패 · 중단된 물류 통보(IF-001) 인터페이스 로그를 「전송대기」로 되돌린다 — 지정한 로그만, 재전송 준비
 * @layer       : Script
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.17   Kai        Created     최초 작성 (D11 Step 6 — LOG-000000 재처리)
 * ======================================================================================
 *  실행 : sf apex run --file scripts/apex/logisticsNotifyRequeueLog.apex --target-org kai-dev
 *         → 이어서 logisticsNotifyWakeUp.apex 실행(이 스크립트는 이벤트를 발행하지 않는다)
 *  NOTE : 아래 logNames에 적은 로그만 바꾼다. 전체 일괄 처리는 하지 않는다(목록이 비면 아무것도 안 함)
 *  NOTE : 상태가 실패 · 중단인 로그만 전송대기로 되돌리고 다음 시도 시각을 비운다.
 *         시도 횟수 · 오류 메시지는 이력으로 남긴다(다음 시도가 횟수를 이어 센다)
 *  NOTE : 익명 실행에서는 SYSTEM_MODE를 쓸 수 없다 — 실행자에게 로그 수정 권한이 필요하다(관리자)
 * ======================================================================================*/
List<String> logNames = new List<String>{ 'LOG-000000' };

Set<String> requeueableStatuses = new Set<String>{
  LogisticsNotifyService.LOG_STATUS_FAILED,
  LogisticsNotifyService.LOG_STATUS_ABORTED
};
List<IntegrationLog__c> requeued = new List<IntegrationLog__c>();
Set<String> foundNames = new Set<String>();
if (!logNames.isEmpty()) {
  for (IntegrationLog__c log : [
    SELECT Id, Name, Status__c, AttemptCount__c, NextAttemptAt__c
    FROM IntegrationLog__c
    WHERE Name IN :logNames
      AND InterfaceId__c = :LogisticsNotifyService.INTERFACE_ID
    WITH USER_MODE
  ]) {
    foundNames.add(log.Name);
    if (requeueableStatuses.contains(log.Status__c)) {
      System.debug(
        LoggingLevel.ERROR,
        '>>> ' + log.Name + ' · ' + log.Status__c + ' → ' + LogisticsNotifyService.LOG_STATUS_PENDING +
        ' (시도 ' + log.AttemptCount__c + '회 유지)'
      );
      requeued.add(
        new IntegrationLog__c(
          Id = log.Id,
          Status__c = LogisticsNotifyService.LOG_STATUS_PENDING,
          NextAttemptAt__c = null
        )
      );
    } else {
      System.debug(LoggingLevel.ERROR, '>>> ' + log.Name + ' · 상태 ' + log.Status__c + ' — 실패 · 중단이 아니라 그대로 둠');
    }
  }
}
for (String logName : logNames) {
  if (!foundNames.contains(logName)) {
    System.debug(LoggingLevel.ERROR, '>>> ' + logName + ' · IF-001 로그 없음 — 그대로 둠');
  }
}
if (requeued.isEmpty()) {
  System.debug(LoggingLevel.ERROR, '>>> 바꾼 로그 없음');
} else {
  update as user requeued;
  System.debug(LoggingLevel.ERROR, '>>> 전송대기로 되돌림 ' + requeued.size() + '건 — 이어서 logisticsNotifyWakeUp.apex 실행');
}
