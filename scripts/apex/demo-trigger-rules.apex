// D5 발표 시연 백업 — 화면 시연이 실패할 때 같은 내용을 Anonymous Apex로 보여준다.
// 끝에서 rollback하므로 데이터는 바뀌지 않는다.
// 실행: sf apex run -o kai-dev --file scripts/apex/demo-trigger-rules.apex  (Developer Console에 붙여 넣어도 됨)
Savepoint sp = Database.setSavepoint();

// --- 1) 상태 전이: 종료 → 점검예정은 막히고, 점검완료 → 시정중은 저장된다
Inspection__c closed = [SELECT Id, Status__c FROM Inspection__c WHERE Status__c = '종료' LIMIT 1];
// NOTE: 시연 2에서 쓸 불합격 점검과 겹치지 않도록 합격 점검을 고른다 (같은 트랜잭션이라 상태가 바뀐 채로 이어짐)
Inspection__c done = [SELECT Id, Status__c FROM Inspection__c WHERE Status__c = '점검완료' AND Judgement__c = '합격' LIMIT 1];
closed.Status__c = '점검예정';
done.Status__c = '시정중';
List<Database.SaveResult> results = Database.update(new List<Inspection__c>{ closed, done }, false);
System.debug(LoggingLevel.ERROR, 'DEMO 1 종료→점검예정 : ' + (results[0].isSuccess() ? '저장됨' : '차단 / ' + results[0].getErrors()[0].getMessage()));
System.debug(LoggingLevel.ERROR, 'DEMO 1 점검완료→시정중 : ' + (results[1].isSuccess() ? '저장됨' : '차단 / ' + results[1].getErrors()[0].getMessage()));

// --- 2) 판정: 점검완료 · 불합격 점검의 필수 미흡을 해제하면 판정이 다시 계산된다
//        점수가 60% 이상이라 필수 미흡 때문에만 불합격인 점검을 고른다 (40점 만점 기준 24점 이상)
Inspection__c failed = [
    SELECT Id, Name, Judgement__c, ruTotalScore__c, ruMaxScore__c, ruDeficientRequiredCount__c
    FROM Inspection__c
    WHERE Status__c = '점검완료' AND Judgement__c = '불합격' AND ruDeficientRequiredCount__c > 0
      AND ruMaxScore__c = 40 AND ruTotalScore__c >= 24
    LIMIT 1
];
InspectionResult__c requiredItem = [
    SELECT Id FROM InspectionResult__c
    WHERE Inspection__c = :failed.Id AND IsRequired__c = true AND IsDeficient__c = true LIMIT 1
];
requiredItem.IsDeficient__c = false;
update requiredItem;
Inspection__c judged = [SELECT Judgement__c, ruDeficientRequiredCount__c FROM Inspection__c WHERE Id = :failed.Id];
System.debug(LoggingLevel.ERROR, 'DEMO 2 판정 ' + failed.Name + ' : ' + failed.Judgement__c + ' → ' + judged.Judgement__c
    + ' (총점 ' + failed.ruTotalScore__c + '/' + failed.ruMaxScore__c + ', 필수 미흡 ' + failed.ruDeficientRequiredCount__c + ' → ' + judged.ruDeficientRequiredCount__c + ')');

// --- 3) 최근 정기점검일: 정기점검이 1건뿐인 가맹점에서 삭제 → null, 복원 → 원래 날짜
Id regularRtId = Schema.SObjectType.Inspection__c.getRecordTypeInfosByDeveloperName().get('Regular').getRecordTypeId();
AggregateResult[] singles = [
    SELECT Franchise__c franchiseId FROM Inspection__c
    WHERE RecordTypeId = :regularRtId AND Status__c != '점검예정' AND InspectionDate__c != null
    GROUP BY Franchise__c HAVING COUNT(Id) = 1 LIMIT 1
];
Id franchiseId = (Id) singles[0].get('franchiseId');
Inspection__c onlyOne = [
    SELECT Id FROM Inspection__c
    WHERE Franchise__c = :franchiseId AND RecordTypeId = :regularRtId AND Status__c != '점검예정' LIMIT 1
];
Date before = [SELECT LastRegularInspectionDate__c FROM Account WHERE Id = :franchiseId].LastRegularInspectionDate__c;
delete onlyOne;
Date afterDelete = [SELECT LastRegularInspectionDate__c FROM Account WHERE Id = :franchiseId].LastRegularInspectionDate__c;
undelete onlyOne;
Date afterUndelete = [SELECT LastRegularInspectionDate__c FROM Account WHERE Id = :franchiseId].LastRegularInspectionDate__c;
System.debug(LoggingLevel.ERROR, 'DEMO 3 최근 정기점검일 : ' + before + ' → 삭제 ' + afterDelete + ' → 복원 ' + afterUndelete);

Database.rollback(sp);
