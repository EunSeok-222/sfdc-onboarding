// D5 벌크 검증 — 점검 트리거가 N건에서도 SOQL · DML 횟수를 유지하는지 확인한다.
// 실행: N 값을 1 / 200 / 400으로 바꿔 sf apex run -o kai-dev --file scripts/apex/bulk-check-trigger.apex
// 끝에서 rollback하므로 데이터는 바뀌지 않는다. 측정값은 DML 문 앞뒤 Limits 차이(트리거가 쓴 양 + DML 1문)다.
Integer N = 1;

Savepoint sp = Database.setSavepoint();
Id regularRtId = Schema.SObjectType.Inspection__c.getRecordTypeInfosByDeveloperName().get('Regular').getRecordTypeId();
List<Account> stores = [SELECT Id FROM Account WHERE StoreCode__c LIKE 'HK-0%' ORDER BY StoreCode__c];

List<Inspection__c> targets = [
    SELECT Id, Franchise__c, InspectionDate__c
    FROM Inspection__c
    WHERE InspectionNo__c LIKE 'BULK-%'
    ORDER BY InspectionNo__c
    LIMIT :Math.min(N, 200)
];

// 400건은 BULK 200건에 임시 점검 200건을 더한다 (insert도 같이 측정)
if (N > 200) {
    List<Inspection__c> extras = new List<Inspection__c>();
    for (Integer i = 0; i < N - 200; i++) {
        extras.add(new Inspection__c(
            InspectionNo__c = 'BULKX-' + String.valueOf(i + 1).leftPad(4, '0'),
            Franchise__c = stores[Math.mod(i, stores.size())].Id,
            RecordTypeId = regularRtId,
            Status__c = '점검완료',
            InspectionDate__c = Date.newInstance(2026, 10, 1)
        ));
    }
    Integer q0 = Limits.getQueries(), d0 = Limits.getDmlStatements(), r0 = Limits.getDmlRows();
    insert extras;
    System.debug(LoggingLevel.ERROR, 'RESULT insert ' + extras.size() + '건 : SOQL +' + (Limits.getQueries() - q0) + ' / DML +' + (Limits.getDmlStatements() - d0) + ' / DML rows +' + (Limits.getDmlRows() - r0));
    targets.addAll(extras);
}

// (a) 날짜 경로: 점검일 · 가맹점 변경 → after update에서 최근 정기점검일 재계산
for (Integer i = 0; i < targets.size(); i++) {
    targets[i].Franchise__c = stores[Math.mod(i, stores.size())].Id;
    targets[i].InspectionDate__c = Date.newInstance(2026, 10, 2);
}
Integer q1 = Limits.getQueries(), d1 = Limits.getDmlStatements(), r1 = Limits.getDmlRows(), c1 = Limits.getCpuTime();
update targets;
System.debug(LoggingLevel.ERROR, 'RESULT (a) 날짜 경로 ' + targets.size() + '건 : SOQL +' + (Limits.getQueries() - q1) + ' / DML +' + (Limits.getDmlStatements() - d1) + ' / DML rows +' + (Limits.getDmlRows() - r1) + ' / CPU +' + (Limits.getCpuTime() - c1) + 'ms');

// (b) 판정 경로: 점검마다 결과 항목 1개 점수 변경 → Roll-Up → 점검 before update에서 판정 재계산
List<InspectionResult__c> items = new List<InspectionResult__c>();
Set<Id> seen = new Set<Id>();
for (InspectionResult__c item : [
    SELECT Id, Inspection__c, Score__c
    FROM InspectionResult__c
    WHERE Inspection__r.InspectionNo__c LIKE 'BULK-%'
    ORDER BY Inspection__r.InspectionNo__c
]) {
    if (seen.size() < Math.min(N, 200) && seen.add(item.Inspection__c)) {
        item.Score__c = (item.Score__c == 10) ? 9 : 10;
        items.add(item);
    }
}
Integer q2 = Limits.getQueries(), d2 = Limits.getDmlStatements(), r2 = Limits.getDmlRows(), c2 = Limits.getCpuTime();
update items;
System.debug(LoggingLevel.ERROR, 'RESULT (b) 판정 경로 결과 항목 ' + items.size() + '건 : SOQL +' + (Limits.getQueries() - q2) + ' / DML +' + (Limits.getDmlStatements() - d2) + ' / DML rows +' + (Limits.getDmlRows() - r2) + ' / CPU +' + (Limits.getCpuTime() - c2) + 'ms');

System.debug(LoggingLevel.ERROR, 'RESULT 트랜잭션 합계 : SOQL ' + Limits.getQueries() + '/' + Limits.getLimitQueries() + ' / DML ' + Limits.getDmlStatements() + '/' + Limits.getLimitDmlStatements() + ' / CPU ' + Limits.getCpuTime() + 'ms');
Database.rollback(sp);
