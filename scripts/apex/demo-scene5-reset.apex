// D7 시연 5번(점검예정 → 점검완료 저장 → 성공 Toast · 판정 갱신)용 데모 점검을 만든다.
// 실행: sf apex run --file scripts/apex/demo-scene5-reset.apex -o kai-dev
// 몇 번 실행해도 결과가 같다 — DEMO-005가 있으면 지우고(결과 항목은 M-D라 함께 삭제) 새로 만든다.
// NOTE: 트리거 전이표상 점검완료 → 점검예정이 불가하므로, 리허설로 점검완료가 된 레코드는 되돌리지 않고 지웠다가 다시 만든다.
//       before insert 트리거가 없어 '점검예정' 신규 insert는 막히지 않는다.
// NOTE: 4항목 34 / 40점(85%), 필수 미흡 0 → 점검완료로 바꾸면 '합격'이 찍힌다.
final String DEMO_NO = 'DEMO-005';
final String OWNER_NAME = '김 길동';
final String FRANCHISE_NAME = '한끼정성 인천송도점';
final Map<String, Decimal> scoresByItemName = new Map<String, Decimal>{
    '냉장고 온도 관리' => 9,
    '주방 바닥 청결' => 8,
    '고객 응대 인사' => 9,
    '조리 순서 준수' => 8
};

Savepoint sp = Database.setSavepoint();
try {
    delete [SELECT Id FROM Inspection__c WHERE InspectionNo__c = :DEMO_NO];

    Inspection__c ins = new Inspection__c(
        InspectionNo__c = DEMO_NO,
        OwnerId = [SELECT Id FROM User WHERE Name = :OWNER_NAME AND IsActive = true LIMIT 1].Id,
        Franchise__c = [SELECT Id FROM Account WHERE Name = :FRANCHISE_NAME LIMIT 1].Id,
        RecordTypeId = Schema.SObjectType.Inspection__c.getRecordTypeInfosByDeveloperName().get('Regular').getRecordTypeId(),
        Status__c = '점검예정',
        InspectionDate__c = Date.newInstance(2026, 10, 14)
    );
    insert ins;

    // DESC: BR-11 스냅샷 — 항목명 · 분류 · 배점 · 필수여부를 활성 템플릿에서 복사한다
    List<InspectionResult__c> results = new List<InspectionResult__c>();
    for (InspectionTemplateItem__c item : [
        SELECT Id, Name, Category__c, MaxScore__c, IsRequired__c
        FROM InspectionTemplateItem__c
        WHERE IsActive__c = true AND Name IN :scoresByItemName.keySet()
        ORDER BY SortOrder__c
    ]) {
        results.add(new InspectionResult__c(
            Inspection__c = ins.Id,
            TemplateItem__c = item.Id,
            ItemName__c = item.Name,
            Category__c = item.Category__c,
            MaxScore__c = item.MaxScore__c,
            IsRequired__c = item.IsRequired__c,
            Score__c = scoresByItemName.get(item.Name),
            IsDeficient__c = false
        ));
    }
    if (results.size() != scoresByItemName.size()) {
        throw new IllegalArgumentException('활성 템플릿 항목이 ' + scoresByItemName.size() + '개가 아닙니다: ' + results.size());
    }
    insert results;

    Inspection__c created = [
        SELECT Name, Status__c, Judgement__c, ruTotalScore__c, ruMaxScore__c, ruDeficientRequiredCount__c, Owner.Name
        FROM Inspection__c WHERE Id = :ins.Id
    ];
    System.debug(LoggingLevel.ERROR, '>>> ' + created.Name + ' | ' + created.Owner.Name + ' | ' + created.Status__c
        + ' | ' + created.ruTotalScore__c + ' / ' + created.ruMaxScore__c
        + ' | 필수 미흡 ' + created.ruDeficientRequiredCount__c + ' | 판정 ' + created.Judgement__c);
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '>>> 실패 — 롤백함: ' + e.getMessage());
}
