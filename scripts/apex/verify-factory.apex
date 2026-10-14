// D6 TestDataFactory 검증 — Factory로 만든 데이터가 Roll-Up · 판정 · 최근 정기점검일까지 제대로 이어지는지 본다.
// 실행: sf apex run --file scripts/apex/verify-factory.apex -o kai-dev
// 끝에서 rollback하므로 org에 데이터가 남지 않는다.
Savepoint sp = Database.setSavepoint();
List<String> lines = new List<String>();
try {
    List<Account> franchises = TestDataFactory.createFranchises(1, true);
    // DESC: 템플릿 10개 중 앞 2개가 필수, 배점 10
    List<InspectionTemplateItem__c> items = TestDataFactory.createTemplateItems(10, 2, 10, true);
    Inspection__c ins = TestDataFactory.createInspections(
        franchises, 1, TestDataFactory.STATUS_SCHEDULED, TestDataFactory.RT_REGULAR, Date.today(), true
    )[0];
    TestDataFactory.createResults(
        ins, items, new List<Decimal>{ 10, 10, 10, 10, 10, 10, 10, 10, 0, 0 }, true
    );

    Inspection__c afterResults = [
        SELECT ruTotalScore__c, ruMaxScore__c, ruDeficientRequiredCount__c, Judgement__c
        FROM Inspection__c WHERE Id = :ins.Id
    ];
    lines.add('① 결과 항목 insert 후 (점검예정)');
    lines.add('   총점      기대 80   / 실제 ' + afterResults.ruTotalScore__c);
    lines.add('   배점      기대 100  / 실제 ' + afterResults.ruMaxScore__c);
    lines.add('   필수미흡  기대 0    / 실제 ' + afterResults.ruDeficientRequiredCount__c);
    lines.add('   판정      기대 null / 실제 ' + afterResults.Judgement__c);

    update new Inspection__c(Id = ins.Id, Status__c = TestDataFactory.STATUS_COMPLETED);

    Inspection__c afterComplete = [SELECT Judgement__c FROM Inspection__c WHERE Id = :ins.Id];
    Date lastDate = [SELECT LastRegularInspectionDate__c FROM Account WHERE Id = :franchises[0].Id]
        .LastRegularInspectionDate__c;
    lines.add('② 점검완료로 update 후');
    lines.add('   판정            기대 합격 / 실제 ' + afterComplete.Judgement__c);
    lines.add('   최근 정기점검일 기대 ' + Date.today() + ' / 실제 ' + lastDate);
} catch (Exception e) {
    lines.add('예외: ' + e.getTypeName() + ' — ' + e.getMessage() + ' @ ' + e.getStackTraceString());
} finally {
    Database.rollback(sp);
}
System.debug(LoggingLevel.ERROR, '\n' + String.join(lines, '\n'));
