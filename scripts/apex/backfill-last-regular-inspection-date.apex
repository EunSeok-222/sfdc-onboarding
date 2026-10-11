// 최근 정기점검일(LastRegularInspectionDate__c) 초기값 채우기 — 트리거 배포 후 1회 실행
// 트리거는 점검이 바뀔 때만 돌기 때문에 기존 가맹점은 이 스크립트로 한 번 계산한다.
// 실행: sf apex run -o kai-dev --file scripts/apex/backfill-last-regular-inspection-date.apex
Map<Id, Account> franchisesById = new Map<Id, Account>([SELECT Id FROM Account]);
FranchiseInspectionDateService.recalculateLastRegularInspectionDates(franchisesById.keySet());

System.debug(LoggingLevel.ERROR, 'BACKFILL 대상 가맹점: ' + franchisesById.size());
System.debug(LoggingLevel.ERROR, 'BACKFILL SOQL ' + Limits.getQueries() + ' / DML ' + Limits.getDmlStatements() + ' / DML rows ' + Limits.getDmlRows());
