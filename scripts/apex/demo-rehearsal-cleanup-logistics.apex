/* ======================================================================================
 * @description : 시연 리허설 산출물 정리(hankki-logistics) — 리허설 페널티의 상관 ID를 가진 출고 제한. 기본은 미리보기
 * @layer       : Script
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 (D11 시연 초기화 — 물류 org 쪽)
 * ======================================================================================
 *  실행 : sf apex run --file scripts/apex/demo-rehearsal-cleanup-logistics.apex --target-org hankki-logistics
 *  순서 : kai-dev demo-rehearsal-cleanup.apex 미리보기가 출력한 「물류 org에 넘길 상관 ID」를 아래 CORRELATION_IDS에
 *         붙여 넣고 미리보기 → EXECUTE = true로 실행(끝나면 false로, 목록은 비워 되돌린다)
 *  NOTE : 두 org는 서로 조회할 수 없어 상관 ID(= kai-dev 페널티 Id)를 사람이 넘긴다. 목록이 비면 아무것도 하지 않는다
 *  NOTE : logistics/ 패키지 오브젝트를 쓴다 — kai-dev에서는 컴파일되지 않는다
 *  WARN : 보존 — SR-000000 ~ 000002(SR-000002는 발표 라이브 시연용). 대상에 섞이면 제외하고 「보존 제외」로 출력한다
 *  NOTE : 익명 실행이라 SYSTEM_MODE를 쓸 수 없다 — 조회는 WITH USER_MODE, 삭제는 실행자 권한(「출고 제한 관리」)
 * ======================================================================================*/
final Boolean EXECUTE = false;
final List<String> CORRELATION_IDS = new List<String>{};
final Set<String> PRESERVED_REQUESTS = new Set<String>{ 'SR-000000', 'SR-000001', 'SR-000002' };

System.debug(LoggingLevel.ERROR, '>>> 모드: ' + (EXECUTE ? '실행(삭제)' : '미리보기(변경 없음)') + ' · 입력 상관 ID ' + CORRELATION_IDS.size() + '건');

List<SupplyRestriction__c> restrictions = new List<SupplyRestriction__c>();
Set<String> foundIds = new Set<String>();
if (!CORRELATION_IDS.isEmpty()) {
  for (SupplyRestriction__c restriction : [
    SELECT Id, Name, StoreCode__c, Status__c, CallbackStatus__c, CorrelationId__c
    FROM SupplyRestriction__c
    WHERE CorrelationId__c IN :CORRELATION_IDS
    WITH USER_MODE
  ]) {
    foundIds.add(restriction.CorrelationId__c);
    if (PRESERVED_REQUESTS.contains(restriction.Name)) {
      System.debug(LoggingLevel.ERROR, '>>> 보존 제외: ' + restriction.Name + ' (' + restriction.CorrelationId__c + ')');
    } else {
      restrictions.add(restriction);
      System.debug(LoggingLevel.ERROR, '>>> 대상 출고 제한 ' + restriction.Name + ' · ' + restriction.StoreCode__c + ' · ' +
        restriction.Status__c + ' · 회신 ' + restriction.CallbackStatus__c + ' · ' + restriction.CorrelationId__c);
    }
  }
}
for (String correlationId : CORRELATION_IDS) {
  if (!foundIds.contains(correlationId)) {
    System.debug(LoggingLevel.ERROR, '>>> ' + correlationId + ' · 출고 제한 없음(물류 통보 전에 리허설이 끝났거나 이미 정리됨)');
  }
}
System.debug(LoggingLevel.ERROR, '>>> 대상 합계: 출고 제한 ' + restrictions.size() + '건');

if (EXECUTE && !restrictions.isEmpty()) {
  Savepoint sp = Database.setSavepoint();
  try {
    delete restrictions;
    System.debug(LoggingLevel.ERROR, '>>> 삭제 완료: 출고 제한 ' + restrictions.size() + '건');
  } catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '>>> 실패 — 롤백함: ' + e.getMessage());
  }
} else if (!EXECUTE) {
  System.debug(LoggingLevel.ERROR, '>>> 미리보기라 아무것도 바꾸지 않았다. 정리하려면 EXECUTE = true');
}
