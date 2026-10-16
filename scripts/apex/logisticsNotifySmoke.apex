// DESC: IF-001 스모크 — kai-dev → hankki-logistics 실호출. 공급 제한 · 승인 · 매장코드 있는 페널티 1건으로
//       LogisticsNotifyService.notifySupplyRestriction을 호출하고 상태코드 · 응답 본문을 남긴다 (D10 Step 4)
// 실행: sf apex run --file scripts/apex/logisticsNotifySmoke.apex -o kai-dev
//       1회차 201(신규 접수) → 같은 명령 2회차 200 + 같은 접수번호(멱등성)
// NOTE: 1회차 · 2회차를 별도 실행으로 나눈다 — 송신 측 재시도는 다른 트랜잭션에서 일어나므로 같은 조건으로 본다
// WARN: DML을 하지 않는다. 콜아웃 앞에 DML이 있으면 "You have uncommitted work pending"으로 막힌다
List<Penalty__c> penalties = [
  SELECT Id, Name, PenaltyType__c, Status__c, StartDate__c, EndDate__c, Reason__c,
         Franchise__r.Name, Franchise__r.StoreCode__c
  FROM Penalty__c
  WHERE PenaltyType__c = :LogisticsNotifyService.PENALTY_TYPE_SUPPLY_RESTRICTION
    AND Status__c = :LogisticsNotifyService.PENALTY_STATUS_APPROVED
    AND Franchise__r.StoreCode__c != null
  ORDER BY Name
  LIMIT 1
];
if (penalties.isEmpty()) {
  System.debug(LoggingLevel.ERROR, '>>> 대상 없음 — 공급 제한 · 승인 · 매장코드 있는 페널티가 없다');
} else {
  Penalty__c penalty = penalties[0];
  System.debug(
    LoggingLevel.ERROR,
    '>>> 대상 ' + penalty.Name + ' (' + penalty.Id + ') · ' + penalty.Franchise__r.Name +
    ' · 매장코드 ' + penalty.Franchise__r.StoreCode__c + ' · ' + penalty.StartDate__c + ' ~ ' + penalty.EndDate__c
  );
  try {
    HttpResponse res = LogisticsNotifyService.notifySupplyRestriction(penalty);
    System.debug(LoggingLevel.ERROR, '>>> 성공 HTTP ' + res.getStatusCode() + ' · 본문=' + res.getBody());
  } catch (LogisticsNotifyService.LogisticsNotifyException e) {
    System.debug(
      LoggingLevel.ERROR,
      '>>> 실패 · statusCode=' + e.statusCode + ' · retryable=' + e.retryable +
      ' · ' + e.getMessage() + ' · 본문=' + e.responseBody
    );
  }
}
