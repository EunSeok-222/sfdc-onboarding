// DESC: LogisticsNotifyService.notifySupplyRestriction을 org에서 실제로 한 번 호출해 실패 분기를 로그로 확인한다 (D8 심화 요건 ①)
// 실행: sf apex run --file scripts/apex/notifySupplyRestriction.apex -o kai-dev
// NOTE: Named Credential HankkiLogistics의 주소는 실제 물류 시스템이 없는 임의 주소다. 연결 실패가 정상이고,
//       프록시가 DNS 실패를 HTTP 503으로 돌려줘 재시도 대상(retryable=true, statusCode=503)으로 떨어진다
//       (근거: scripts/apex/checkCalloutResponse.apex 헤더 · 실측)
// NOTE: 실행 사용자에게 External Credential 주체 접근 권한이 없으면 연결 전에 권한 오류로 끝난다 — 이것도 재시도 불가 분기다
// WARN: DML을 하지 않는다. 콜아웃 앞에 DML이 있으면 "You have uncommitted work pending"으로 막힌다
Penalty__c penalty = [
  SELECT Id, Name, PenaltyType__c, Status__c, StartDate__c, EndDate__c, Reason__c,
         Franchise__r.Name, Franchise__r.StoreCode__c
  FROM Penalty__c
  WHERE PenaltyType__c = :LogisticsNotifyService.PENALTY_TYPE_SUPPLY_RESTRICTION
    AND Status__c = :LogisticsNotifyService.PENALTY_STATUS_APPROVED
  LIMIT 1
];
// DESC: org의 시연 페널티는 기간이 비어 있어 검증에서 먼저 거절된다 — 메모리에서만 채운다(저장하지 않음)
if (penalty.StartDate__c == null || penalty.EndDate__c == null) {
  penalty.StartDate__c = Date.today().addDays(1);
  penalty.EndDate__c = Date.today().addDays(7);
}
System.debug(
  LoggingLevel.ERROR,
  '>>> 대상 ' + penalty.Name + ' · ' + penalty.Franchise__r.Name + ' · 매장코드 ' + penalty.Franchise__r.StoreCode__c +
  ' · ' + penalty.StartDate__c + ' ~ ' + penalty.EndDate__c
);

try {
  HttpResponse res = LogisticsNotifyService.notifySupplyRestriction(penalty);
  System.debug(LoggingLevel.ERROR, '>>> 성공 HTTP ' + res.getStatusCode());
} catch (LogisticsNotifyService.LogisticsNotifyException e) {
  System.debug(
    LoggingLevel.ERROR,
    '>>> 실패 · retryable=' + e.retryable + ' · statusCode=' + e.statusCode +
    ' · 분기=' + (e.retryable ? '재시도 대상' : '재시도 불가(사람 확인)') +
    ' · ' + e.getMessage()
  );
}
