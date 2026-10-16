// DESC: IF-001 스모크 준비 — PEN-000001의 제한 기간(StartDate__c · EndDate__c)만 저장한다 (D10 Step 4)
// 실행: sf apex run --file scripts/apex/logisticsSmokePrepare.apex -o kai-dev  (logisticsNotifySmoke.apex보다 먼저, 별도 실행)
// NOTE: 승인 잠금 레코드(finalApprovalRecordLock, 편집 = 관리자만)라 관리자로 실행한다.
//       Id와 두 날짜만 담은 sObject로 update해 다른 필드는 건드리지 않는다
// WARN: 콜아웃과 같은 실행에 두지 않는다 — DML 뒤 콜아웃은 "You have uncommitted work pending"
Penalty__c target = [
  SELECT Id, Name, StartDate__c, EndDate__c
  FROM Penalty__c
  WHERE Name = 'PEN-000001'
];
System.debug(
  LoggingLevel.ERROR,
  '>>> 저장 전 ' + target.Name + ' (' + target.Id + ') · ' + target.StartDate__c + ' ~ ' + target.EndDate__c
);

update new Penalty__c(
  Id = target.Id,
  StartDate__c = Date.newInstance(2026, 10, 17),
  EndDate__c = Date.newInstance(2026, 10, 23)
);

Penalty__c saved = [
  SELECT Id, Name, StartDate__c, EndDate__c
  FROM Penalty__c
  WHERE Id = :target.Id
];
System.debug(
  LoggingLevel.ERROR,
  '>>> 저장 후 ' + saved.Name + ' (' + saved.Id + ') · ' + saved.StartDate__c + ' ~ ' + saved.EndDate__c
);
