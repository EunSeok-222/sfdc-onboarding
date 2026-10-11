// D5 Order of Execution 확인 — 저장 1번이 어떤 순서로 무엇을 실행하는지 Debug Log로 본다.
// 실행: Developer Console Execute Anonymous (Open Log 체크) → Debug Only 해제 → Filter CODE_UNIT 또는 VALIDATION
// 끝에서 rollback하므로 데이터는 바뀌지 않는다.
Savepoint sp = Database.setSavepoint();

// 대상: 점검완료 · 정기점검 · 점검일이 있는 점검의 일반(필수 아님) 결과 항목 1건
Inspection__c ins = [
    SELECT Id, Name, Judgement__c, ruTotalScore__c, Franchise__c, InspectionDate__c
    FROM Inspection__c
    WHERE Status__c = '점검완료' AND RecordType.DeveloperName = 'Regular'
      AND InspectionDate__c != null AND InspectionNo__c LIKE 'MIG-%'
    LIMIT 1
];
InspectionResult__c item = [
    SELECT Id, Score__c, MaxScore__c FROM InspectionResult__c
    WHERE Inspection__c = :ins.Id AND IsRequired__c = false AND Score__c < 10
    LIMIT 1
];

// --- 연쇄 ① 결과 항목 점수 저장 → Validation Rule → Roll-Up → 점검 트리거(before · after)
System.debug(LoggingLevel.ERROR, 'OOE ① 시작 · ' + ins.Name + ' 결과 항목 점수 ' + item.Score__c + ' → ' + (item.Score__c + 1));
item.Score__c = item.Score__c + 1;
update item;
Inspection__c afterScore = [SELECT Judgement__c, ruTotalScore__c FROM Inspection__c WHERE Id = :ins.Id];
System.debug(LoggingLevel.ERROR, 'OOE ① 끝 · 총점 ' + ins.ruTotalScore__c + ' → ' + afterScore.ruTotalScore__c + ' · 판정 ' + ins.Judgement__c + ' → ' + afterScore.Judgement__c);

// --- 연쇄 ② 점검일 변경 → 점검 트리거(before · after) → 가맹점 최근 정기점검일 update
System.debug(LoggingLevel.ERROR, 'OOE ② 시작 · ' + ins.Name + ' 점검일 ' + ins.InspectionDate__c + ' → ' + ins.InspectionDate__c.addDays(1));
Date beforeDate = [SELECT LastRegularInspectionDate__c FROM Account WHERE Id = :ins.Franchise__c].LastRegularInspectionDate__c;
update new Inspection__c(Id = ins.Id, InspectionDate__c = ins.InspectionDate__c.addDays(1));
Date afterDate = [SELECT LastRegularInspectionDate__c FROM Account WHERE Id = :ins.Franchise__c].LastRegularInspectionDate__c;
System.debug(LoggingLevel.ERROR, 'OOE ② 끝 · 가맹점 최근 정기점검일 ' + beforeDate + ' → ' + afterDate);

Database.rollback(sp);
