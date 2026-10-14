// D6 필드 메타데이터 조사 — TestDataFactory 작성 전에 커스텀 오브젝트 4종의 실제 API Name과 필수 여부를 확정한다.
// 실행: sf apex run --file scripts/apex/describe-fields.apex -o kai-dev
// 조회만 하므로 데이터는 바뀌지 않는다.
// NOTE: isCreateable()은 실행 사용자의 FLS 기준이다. 시스템 관리자로 실행해야 org 전체 기준과 같다.
List<String> objectNames = new List<String>{
    'Inspection__c', 'InspectionResult__c', 'InspectionTemplateItem__c', 'CorrectiveAction__c'
};
Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
List<String> lines = new List<String>();

for (String objectName : objectNames) {
    Schema.SObjectType objectType = globalDescribe.get(objectName);
    if (objectType == null) {
        lines.add('');
        lines.add('### ' + objectName + ' — 오브젝트 없음');
        continue;
    }
    Map<String, Schema.SObjectField> fieldsByName = objectType.getDescribe().fields.getMap();

    // DESC: getMap() 순서는 보장되지 않으므로 API Name 기준으로 정렬해 출력을 고정한다.
    List<String> sortedNames = new List<String>();
    Map<String, Schema.DescribeFieldResult> describesByName = new Map<String, Schema.DescribeFieldResult>();
    for (Schema.SObjectField field : fieldsByName.values()) {
        Schema.DescribeFieldResult dfr = field.getDescribe();
        if (!dfr.isCustom() && !dfr.isNameField()) {
            continue;
        }
        sortedNames.add(dfr.getName());
        describesByName.put(dfr.getName(), dfr);
    }
    sortedNames.sort();

    lines.add('');
    lines.add('### ' + objectName + ' (' + objectType.getDescribe().getLabel() + ')');
    lines.add('API Name | 타입 | 필수 | 생성가능 | 참조대상/Picklist 값');

    for (String fieldName : sortedNames) {
        Schema.DescribeFieldResult dfr = describesByName.get(fieldName);
        Boolean isRequired = !dfr.isNillable() && dfr.isCreateable() && !dfr.isDefaultedOnCreate();

        String extra = '';
        Schema.DisplayType fieldType = dfr.getType();
        if (fieldType == Schema.DisplayType.REFERENCE) {
            List<String> targets = new List<String>();
            for (Schema.SObjectType target : dfr.getReferenceTo()) {
                targets.add(String.valueOf(target));
            }
            extra = '→ ' + String.join(targets, ', ');
        } else if (fieldType == Schema.DisplayType.PICKLIST || fieldType == Schema.DisplayType.MULTIPICKLIST) {
            List<String> values = new List<String>();
            for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                if (entry.isActive()) {
                    values.add(entry.getValue());
                }
            }
            extra = '[' + String.join(values, ', ') + ']';
        }

        lines.add(String.join(new List<String>{
            dfr.getName(),
            String.valueOf(fieldType),
            isRequired ? 'Y' : '-',
            dfr.isCreateable() ? 'Y' : '-',
            extra
        }, ' | '));
    }
}

System.debug(LoggingLevel.ERROR, '\n' + String.join(lines, '\n'));
