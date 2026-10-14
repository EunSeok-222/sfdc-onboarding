// DESC: InspectionListController.search를 org 실데이터로 한 번 호출해 결과 건수를 확인한다 (D7 덩어리 2)
// NOTE: 실행 사용자 기준 sharing이 적용된다. 관리자로 실행하면 전체가, SV로 실행하면 담당 매장만 보인다
InspectionListController.SearchCriteria criteria = new InspectionListController.SearchCriteria();
criteria.pageSize = 20;
criteria.pageNumber = 1;

InspectionListController.InspectionPageWrapper page = InspectionListController.search(criteria);
System.debug(LoggingLevel.ERROR, '>>> totalCount = ' + page.totalCount + ', records = ' + page.records.size());
for (Inspection__c ins : page.records) {
  System.debug(
    LoggingLevel.ERROR,
    '>>> ' + ins.Name + ' | ' + ins.Franchise__r.Name + ' | ' + ins.InspectionDate__c + ' | ' +
    ins.RecordType.Name + ' | ' + ins.Status__c + ' | ' + ins.ruTotalScore__c + ' | ' + ins.Judgement__c
  );
}
