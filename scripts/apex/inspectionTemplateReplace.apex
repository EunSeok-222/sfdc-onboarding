/* ======================================================================================
 * @description : 점검표를 새 20항목(위생 40 · 서비스 30 · 매뉴얼 30 = 100점, 위생 필수 6)으로 교체한다
 * @layer       : Script
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 (D11 D1 점검표 재구성 — 요건 정의서 V1.1 BR-02 · 03 · 11)
 * ======================================================================================
 *  실행 : sf apex run --file scripts/apex/inspectionTemplateReplace.apex --target-org kai-dev
 *  NOTE : 몇 번 실행해도 결과가 같다 — 새 항목은 이름으로 찾아 있으면 값만 맞추고(비활성이면 다시 사용 중), 없으면 만든다.
 *         그 밖의 사용 중 항목은 비활성으로 바꾼다
 *  NOTE : 기존 항목은 삭제하지 않는다 — 과거 결과 항목이 Restrict 조회로 참조하고, 결과에는 당시 항목 · 배점이
 *         스냅샷으로 남는다(BR-11)
 *  NOTE : 끝에 사용 중 항목 수 · 배점 합계 · 필수 수를 검증한다. 20 · 100 · 6이 아니면 전부 되돌린다
 *  WARN : 템플릿 데이터를 바꾼다. 검증 규칙 RequiredOnlyForSanitation(필수는 위생만) 배포 뒤에 실행한다.
 *         익명 실행이라 SYSTEM_MODE를 쓸 수 없다 — 실행자에게 점검표 항목 편집 권한이 필요하다(관리자)
 * ======================================================================================*/
// 순서 · 분류 · 항목명 · 배점 · 위생 필수
final List<List<Object>> ROWS = new List<List<Object>>{
  new List<Object>{ 10, '위생', '냉장·냉동 온도 기록', 5, true },
  new List<Object>{ 20, '위생', '식자재 유통기한 관리', 5, true },
  new List<Object>{ 30, '위생', '조리자 위생복·위생모 착용', 5, true },
  new List<Object>{ 40, '위생', '손 세척·소독 설비 비치', 5, true },
  new List<Object>{ 50, '위생', '칼·도마 용도별 구분(교차오염 방지)', 5, true },
  new List<Object>{ 60, '위생', '방충·방서 관리 기록', 5, true },
  new List<Object>{ 70, '위생', '주방 바닥·배수구 청결', 5, false },
  new List<Object>{ 80, '위생', '식기 세척·소독 상태', 5, false },
  new List<Object>{ 90, '서비스', '고객 맞이 인사·안내', 5, false },
  new List<Object>{ 100, '서비스', '주문 내용 복창 확인', 5, false },
  new List<Object>{ 110, '서비스', '음식 제공 시간 준수', 5, false },
  new List<Object>{ 120, '서비스', '홀·화장실 청결', 5, false },
  new List<Object>{ 130, '서비스', '고객 불만 응대·기록', 5, false },
  new List<Object>{ 140, '서비스', '메뉴판·가격 표시 정확성', 5, false },
  new List<Object>{ 150, '매뉴얼', '표준 조리 순서 준수', 5, false },
  new List<Object>{ 160, '매뉴얼', '레시피 계량 기준 준수', 5, false },
  new List<Object>{ 170, '매뉴얼', '담음새(플레이팅) 기준 준수', 5, false },
  new List<Object>{ 180, '매뉴얼', '원산지 표시', 5, false },
  new List<Object>{ 190, '매뉴얼', '개점·마감 점검표 작성', 5, false },
  new List<Object>{ 200, '매뉴얼', '본사 지정 식자재 사용', 5, false }
};
final Integer EXPECTED_COUNT = 20;
final Decimal EXPECTED_TOTAL = 100;
final Integer EXPECTED_REQUIRED = 6;

Map<String, InspectionTemplateItem__c> wantedByName = new Map<String, InspectionTemplateItem__c>();
for (List<Object> row : ROWS) {
  InspectionTemplateItem__c item = new InspectionTemplateItem__c(
    SortOrder__c = (Integer) row[0],
    Category__c = (String) row[1],
    Name = (String) row[2],
    MaxScore__c = (Integer) row[3],
    IsRequired__c = (Boolean) row[4],
    IsActive__c = true
  );
  wantedByName.put(item.Name, item);
}

Savepoint sp = Database.setSavepoint();
try {
  // DESC: 같은 이름이 이미 있으면 그 레코드를 갱신한다 — 다시 실행해도 항목이 늘지 않는다
  Integer reused = 0;
  for (InspectionTemplateItem__c existing : [
    SELECT Id, Name
    FROM InspectionTemplateItem__c
    WHERE Name IN :wantedByName.keySet()
    WITH USER_MODE
  ]) {
    wantedByName.get(existing.Name).Id = existing.Id;
    reused++;
  }
  List<InspectionTemplateItem__c> deactivated = new List<InspectionTemplateItem__c>();
  for (InspectionTemplateItem__c old : [
    SELECT Id, Name
    FROM InspectionTemplateItem__c
    WHERE IsActive__c = TRUE AND Name NOT IN :wantedByName.keySet()
    WITH USER_MODE
  ]) {
    deactivated.add(new InspectionTemplateItem__c(Id = old.Id, IsActive__c = false));
    System.debug(LoggingLevel.ERROR, '>>> 비활성: ' + old.Name);
  }
  update as user deactivated;
  upsert as user wantedByName.values();

  Integer activeCount = 0;
  Decimal totalScore = 0;
  Integer requiredCount = 0;
  Map<String, Decimal> scoreByCategory = new Map<String, Decimal>();
  for (InspectionTemplateItem__c item : [
    SELECT Category__c, MaxScore__c, IsRequired__c
    FROM InspectionTemplateItem__c
    WHERE IsActive__c = TRUE
    WITH USER_MODE
  ]) {
    activeCount++;
    totalScore += item.MaxScore__c;
    requiredCount += item.IsRequired__c ? 1 : 0;
    Decimal categoryScore = scoreByCategory.get(item.Category__c);
    scoreByCategory.put(item.Category__c, (categoryScore == null ? 0 : categoryScore) + item.MaxScore__c);
  }
  System.debug(
    LoggingLevel.ERROR,
    '>>> 새로 만듦 ' + (EXPECTED_COUNT - reused) + ' · 기존 갱신 ' + reused + ' · 비활성 ' + deactivated.size()
  );
  System.debug(
    LoggingLevel.ERROR,
    '>>> 사용 중 ' + activeCount + '항목 · 배점 합계 ' + totalScore + ' · 위생 필수 ' + requiredCount +
    ' · 분류별 ' + JSON.serialize(scoreByCategory)
  );
  if (activeCount != EXPECTED_COUNT || totalScore != EXPECTED_TOTAL || requiredCount != EXPECTED_REQUIRED) {
    throw new IllegalArgumentException(
      '검증 실패 — 사용 중 ' + activeCount + '/' + EXPECTED_COUNT + ', 합계 ' + totalScore + '/' + EXPECTED_TOTAL +
      ', 필수 ' + requiredCount + '/' + EXPECTED_REQUIRED
    );
  }
} catch (Exception e) {
  Database.rollback(sp);
  System.debug(LoggingLevel.ERROR, '>>> 실패 — 롤백함: ' + e.getMessage());
}
