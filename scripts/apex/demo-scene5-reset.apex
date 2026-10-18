// D7 시연 5번(점검예정 → 점검완료 저장 → 성공 Toast · 판정 갱신)용 데모 점검을 만든다.
// 실행: sf apex run --file scripts/apex/demo-scene5-reset.apex -o kai-dev
// 이력: 2026.10.18 Kai 새 점검표(20항목 · 100점)로 다시 작성 — 합격 · 필수 미흡 불합격 두 시나리오(D1)
// 이력: 2026.10.18 Kai DEMO-006 결과 2행(식자재 유통기한 관리 · 메뉴판·가격 표시 정확성)은 점수를 비움 — 라이브에서 입력(D11)
// 몇 번 실행해도 결과가 같다 — DEMO-005 · DEMO-006이 있으면 지우고(결과 항목은 M-D라 함께 삭제) 새로 만든다.
// NOTE: 트리거 전이표상 점검완료 → 점검예정이 불가하므로, 리허설로 점검완료가 된 레코드는 되돌리지 않고 지웠다가 다시 만든다.
//       before insert 트리거가 없어 '점검예정' 신규 insert는 막히지 않는다.
// NOTE: 결과 항목에는 템플릿과 점수만 넣는다 — 항목명 · 분류 · 배점 · 필수(스냅샷)와 미흡은 결과 항목 트리거가 채운다
//       (미흡 = 점수 < 배점 × 0.6 → 5점 항목은 3점 미만이면 미흡)
// NOTE: DEMO-005 합격 — 94 / 100, 비필수 미흡 1개(메뉴판 2점)는 감점만, 3점(음식 제공 시간)은 경계값이라 정상
//       DEMO-006 — 18행만 점수(90 / 100 · 미흡 0), 식자재 유통기한 관리(위생 필수) · 메뉴판·가격 표시 정확성 2행은 점수를 비워 둔다.
//       라이브에서 두 행에 2점을 넣으면 필수 미흡 1 → 점검완료 시 불합격(BR-03). 이관번호 DEMO-006이 있어 점검 트리거의 자동 생성은 돌지 않는다
final String OWNER_NAME = '김 길동';
final Integer EXPECTED_ITEMS = 20;
final Decimal FULL_SCORE = 5;
// 점검번호 → 가맹점 / 만점이 아닌 항목의 점수(null = 점수를 비워 둠)
final Map<String, String> FRANCHISE_BY_DEMO = new Map<String, String>{
    'DEMO-005' => '한끼정성 인천송도점',
    'DEMO-006' => '한끼정성 의정부점'
};
final Map<String, Map<String, Decimal>> DEDUCTIONS_BY_DEMO = new Map<String, Map<String, Decimal>>{
    'DEMO-005' => new Map<String, Decimal>{
        '음식 제공 시간 준수' => 3,
        '홀·화장실 청결' => 4,
        '메뉴판·가격 표시 정확성' => 2
    },
    'DEMO-006' => new Map<String, Decimal>{
        '식자재 유통기한 관리' => null,
        '메뉴판·가격 표시 정확성' => null
    }
};

Savepoint sp = Database.setSavepoint();
try {
    List<InspectionTemplateItem__c> templates = [
        SELECT Id, Name
        FROM InspectionTemplateItem__c
        WHERE IsActive__c = true
        ORDER BY SortOrder__c
    ];
    if (templates.size() != EXPECTED_ITEMS) {
        throw new IllegalArgumentException('사용 중 점검표 항목이 ' + EXPECTED_ITEMS + '개가 아닙니다: ' + templates.size()
            + ' — scripts/apex/inspectionTemplateReplace.apex 먼저 실행');
    }
    Set<String> templateNames = new Set<String>();
    for (InspectionTemplateItem__c template : templates) {
        templateNames.add(template.Name);
    }
    for (Map<String, Decimal> deductions : DEDUCTIONS_BY_DEMO.values()) {
        if (!templateNames.containsAll(deductions.keySet())) {
            throw new IllegalArgumentException('감점 항목 이름이 점검표에 없습니다: ' + deductions.keySet());
        }
    }

    delete [SELECT Id FROM Inspection__c WHERE InspectionNo__c IN :FRANCHISE_BY_DEMO.keySet()];

    Id ownerId = [SELECT Id FROM User WHERE Name = :OWNER_NAME AND IsActive = true LIMIT 1].Id;
    Map<String, Id> franchiseIdByName = new Map<String, Id>();
    for (Account franchise : [SELECT Id, Name FROM Account WHERE Name IN :FRANCHISE_BY_DEMO.values()]) {
        franchiseIdByName.put(franchise.Name, franchise.Id);
    }
    List<Inspection__c> inspections = new List<Inspection__c>();
    for (String demoNo : FRANCHISE_BY_DEMO.keySet()) {
        inspections.add(new Inspection__c(
            InspectionNo__c = demoNo,
            OwnerId = ownerId,
            Franchise__c = franchiseIdByName.get(FRANCHISE_BY_DEMO.get(demoNo)),
            RecordTypeId = Schema.SObjectType.Inspection__c.getRecordTypeInfosByDeveloperName().get('Regular').getRecordTypeId(),
            Status__c = '점검예정',
            InspectionDate__c = Date.today()
        ));
    }
    insert inspections;

    List<InspectionResult__c> results = new List<InspectionResult__c>();
    for (Inspection__c ins : inspections) {
        Map<String, Decimal> deductions = DEDUCTIONS_BY_DEMO.get(ins.InspectionNo__c);
        for (InspectionTemplateItem__c template : templates) {
            results.add(new InspectionResult__c(
                Inspection__c = ins.Id,
                TemplateItem__c = template.Id,
                Score__c = deductions.containsKey(template.Name) ? deductions.get(template.Name) : FULL_SCORE
            ));
        }
    }
    insert results;

    Map<Id, Integer> blankCountByInspectionId = new Map<Id, Integer>();
    for (AggregateResult blank : [
        SELECT Inspection__c insId, COUNT(Id) cnt
        FROM InspectionResult__c
        WHERE Inspection__c IN :inspections AND Score__c = null
        GROUP BY Inspection__c
    ]) {
        blankCountByInspectionId.put((Id) blank.get('insId'), (Integer) blank.get('cnt'));
    }
    for (Inspection__c created : [
        SELECT Name, InspectionNo__c, Franchise__r.Name, Owner.Name, Status__c, Judgement__c,
            ruTotalScore__c, ruMaxScore__c, ruDeficientRequiredCount__c,
            (SELECT Id FROM InspectionInspectionResults__r WHERE IsDeficient__c = true)
        FROM Inspection__c
        WHERE Id IN :inspections
        ORDER BY InspectionNo__c
    ]) {
        System.debug(LoggingLevel.ERROR, '>>> ' + created.InspectionNo__c + ' ' + created.Name + ' | ' + created.Franchise__r.Name
            + ' | ' + created.Owner.Name + ' | ' + created.Status__c
            + ' | ' + created.ruTotalScore__c + ' / ' + created.ruMaxScore__c
            + ' | 미흡 ' + created.InspectionInspectionResults__r.size() + ' (필수 ' + created.ruDeficientRequiredCount__c + ')'
            + ' | 점수 비움 ' + (blankCountByInspectionId.containsKey(created.Id) ? blankCountByInspectionId.get(created.Id) : 0) + '행'
            + ' | 점검완료 시 예상 판정 ' + (created.ruDeficientRequiredCount__c > 0 ? '불합격' : '합격'));
    }
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '>>> 실패 — 롤백함: ' + e.getMessage());
}
