// DESC: CorrectiveActionController.getByInspection을 org 실데이터로 한 번 호출해 결과를 확인한다 (D8 A 전제 작업)
// NOTE: 실행 사용자 기준 sharing · FLS가 적용된다. 관리자로 실행하면 전체가, SV로 실행하면 담당 매장 점검만 보인다
// DESC: 시정조치가 가장 많이 달린 점검 1건을 고른다 (BULK- 테스트 데이터는 제외)
AggregateResult[] countsByInspection = [
  SELECT InspectionResult__r.Inspection__c inspectionId, COUNT(Id) actionCount
  FROM CorrectiveAction__c
  WHERE NOT InspectionResult__r.Inspection__r.InspectionNo__c LIKE 'BULK-%'
  GROUP BY InspectionResult__r.Inspection__c
  ORDER BY COUNT(Id) DESC
  LIMIT 1
];
// WARN: 시정조치가 한 건도 없는 org면 아래 [0]에서 ListException — 그때는 데이터부터 만든다
Id inspectionId = (Id) countsByInspection[0].get('inspectionId');
Inspection__c inspection = [
  SELECT Name, Franchise__r.Name, Status__c
  FROM Inspection__c
  WHERE Id = :inspectionId
];

List<CorrectiveAction__c> actions = CorrectiveActionController.getByInspection(inspectionId);
System.debug(
  LoggingLevel.ERROR,
  '>>> 점검 ' + inspection.Name + ' (' + inspection.Franchise__r.Name + ', ' + inspection.Status__c + ') · 시정조치 ' +
  actions.size() + '건'
);
for (CorrectiveAction__c action : actions) {
  System.debug(
    LoggingLevel.ERROR,
    '>>> ' + action.Name + ' | ' + action.InspectionResult__r.ItemName__c +
    ' | 필수 ' + action.InspectionResult__r.IsRequired__c + ' | ' + action.Status__c +
    ' | 기한 ' + action.DueDate__c + ' | 재방문 ' + action.RequiresRevisit__c
  );
}
System.debug(LoggingLevel.ERROR, '>>> null 호출 = ' + CorrectiveActionController.getByInspection(null).size() + '건');
