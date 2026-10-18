/* ======================================================================================
 * @description : 시연 리허설 산출물 정리(kai-dev) — DEMO-005 · 006에서 생긴 페널티 · 인터페이스 로그. 기본은 미리보기
 * @layer       : Script
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 (D11 시연 초기화 — 점검 리셋 앞 단계)
 *  2026.10.18   Kai        Updated     라이브에서 새로 만든 의정부점 정기점검(이관번호 없음 · DEMO-006 이후)도 정리 대상에 추가
 *  2026.10.18   Kai        Updated     승인 잠금 표시를 Approval.isLocked → 상태(승인대기 · 승인)로 변경 — Apex 잠금 API 설정을 꺼서 실패
 *  2026.10.18   Kai        Updated     보존 추가 — INS-202610-0038 · PEN-000006(demo-story-uijeongbu 의정부점 9월 불합격 · 경고)
 * ======================================================================================
 *  실행 : sf apex run --file scripts/apex/demo-rehearsal-cleanup.apex --target-org kai-dev
 *  순서 : 1) 이 스크립트 미리보기(EXECUTE = false) → 대상과 「물류 org에 넘길 상관 ID」 확인
 *         2) EXECUTE = true로 실행(끝나면 false로 되돌린다)
 *         3) demo-rehearsal-cleanup-logistics.apex(hankki-logistics)에 1)의 상관 ID를 넣어 미리보기 → 실행
 *         4) demo-scene5-reset.apex 실행 → DEMO-005 · 006 점검(결과 20행)을 다시 만든다 — 점검은 이 스크립트가 지우지 않는다
 *  NOTE : 정리 대상 = 리허설에서 생긴 것만
 *         - 근거 점검이 DEMO-005 · 006인 페널티
 *         - 근거 점검이 비었어도 가맹점이 인천송도점 · 의정부점이고 DEMO 점검보다 나중에 만든 페널티
 *           (점검을 지우면 페널티 → 근거 점검 조회가 SetNull로 비기 때문)
 *         - 그 페널티의 인터페이스 로그(페널티 조회 또는 상관 ID 일치) — 로그 → 페널티 조회도 SetNull이라 페널티만 지우면 로그가 남는다
 *         - 라이브에서 「정기점검 생성」으로 만든 의정부점 정기점검(이관번호 없음 · DEMO-006 이후 생성) — 결과 항목 · 시정조치는
 *           Master-Detail이라 점검과 함께 삭제된다. 그 점검을 근거로 한 페널티도 대상
 *  NOTE : 삭제 순서 = 로그 → 페널티 → 라이브 점검. 점검을 지우면 결과 항목 · 시정조치는 Master-Detail이라 함께 삭제되고,
 *         다른 점검의 원 점검 조회는 SetNull이다(Restrict 없음)
 *  WARN : demo-scene5-reset보다 먼저 실행한다 — 리셋이 먼저 돌면 DEMO 점검이 새로 만들어져 「DEMO보다 나중」 기준이 바뀌고
 *         리허설 페널티의 근거 점검이 비어 대상에서 빠질 수 있다
 *  WARN : 보존 — PEN-000000 ~ 000003, LOG-000000 ~ 000002(E2E 증거). 대상에 섞이면 제외하고 「보존 제외」로 출력한다.
 *         PEN-000002 · 000003은 사유가 DEMO-로 시작하지만 사유 접두로는 고르지 않는다
 *  WARN : 보존 — 시연 이야기 데이터(demo-story-uijeongbu) INS-202610-0038 · PEN-000006(의정부점 9월 불합격 · 경고).
 *         지금 조건에는 걸리지 않지만(이관번호 있음 · 근거 점검 있음) INS-0038이 지워지면 PEN-000006의 근거 점검이 SetNull로 비어
 *         「근거 없음 · DEMO 가맹점 · DEMO 이후 생성」 조건에 걸릴 수 있어 번호로 고정해 둔다
 *  WARN : 승인 잠금(승인 완료 · 승인 대기) 페널티 삭제는 관리자(데이터 전체 수정) 실행이 전제다
 *  NOTE : 익명 실행이라 SYSTEM_MODE를 쓸 수 없다 — 조회는 WITH USER_MODE, 삭제는 실행자(관리자) 권한
 * ======================================================================================*/
final Boolean EXECUTE = false;
final Set<String> DEMO_NOS = new Set<String>{ 'DEMO-005', 'DEMO-006' };
final Set<String> DEMO_FRANCHISES = new Set<String>{ '한끼정성 인천송도점', '한끼정성 의정부점' };
final Set<String> PRESERVED_PENALTIES = new Set<String>{ 'PEN-000000', 'PEN-000001', 'PEN-000002', 'PEN-000003', 'PEN-000006' };
final Set<String> PRESERVED_LOGS = new Set<String>{ 'LOG-000000', 'LOG-000001', 'LOG-000002' };
final Set<String> PRESERVED_INSPECTIONS = new Set<String>{ 'INS-202610-0038' };

System.debug(LoggingLevel.ERROR, '>>> 모드: ' + (EXECUTE ? '실행(삭제)' : '미리보기(변경 없음)'));

// DESC: 1) 지금의 DEMO 점검 ↔ INS 대응(리셋하면 INS 번호가 새로 바뀐다)
List<Inspection__c> demos = [
  SELECT Id, Name, InspectionNo__c, Status__c, Judgement__c, CreatedDate
  FROM Inspection__c
  WHERE InspectionNo__c IN :DEMO_NOS
  WITH USER_MODE
  ORDER BY InspectionNo__c
];
Datetime cutoff;
for (Inspection__c demo : demos) {
  System.debug(LoggingLevel.ERROR, '>>> 현재 ' + demo.InspectionNo__c + ' ↔ ' + demo.Name + ' · ' + demo.Status__c +
    ' · 판정 ' + demo.Judgement__c + ' · 생성 ' + demo.CreatedDate);
  if (cutoff == null || demo.CreatedDate < cutoff) {
    cutoff = demo.CreatedDate;
  }
}
Set<Id> demoIds = new Map<Id, Inspection__c>(demos).keySet();

// DESC: 1-b) 라이브에서 새로 만든 의정부점 정기점검 — 이관번호 없음 · DEMO 가맹점 · DEMO 점검 이후 생성
List<Inspection__c> liveInspections = new List<Inspection__c>();
if (cutoff != null) {
  for (Inspection__c live : [
    SELECT Id, Name, Status__c, Judgement__c, Franchise__r.Name, CreatedDate
    FROM Inspection__c
    WHERE InspectionNo__c = NULL AND RecordType.DeveloperName = 'Regular'
      AND Franchise__r.Name IN :DEMO_FRANCHISES AND CreatedDate > :cutoff
    WITH USER_MODE
  ]) {
    if (PRESERVED_INSPECTIONS.contains(live.Name)) {
      System.debug(LoggingLevel.ERROR, '>>> 보존 제외: ' + live.Name);
      continue;
    }
    liveInspections.add(live);
    System.debug(LoggingLevel.ERROR, '>>> 대상 라이브 점검 ' + live.Name + ' · ' + live.Franchise__r.Name + ' · ' + live.Status__c +
      ' · 판정 ' + live.Judgement__c + ' (결과 항목 · 시정조치 함께 삭제)');
  }
}
Set<Id> sourceInspectionIds = new Set<Id>(demoIds);
sourceInspectionIds.addAll(new Map<Id, Inspection__c>(liveInspections).keySet());

// DESC: 2) 대상 페널티 후보 — 근거 점검이 DEMO + (근거 점검이 비었고 DEMO 가맹점 · DEMO 이후 생성)
Map<Id, Penalty__c> candidatesById = new Map<Id, Penalty__c>();
if (!demoIds.isEmpty()) {
  candidatesById.putAll([
    SELECT Id, Name, PenaltyType__c, Status__c, Franchise__r.Name, SourceInspection__r.InspectionNo__c, CreatedDate
    FROM Penalty__c
    WHERE SourceInspection__c IN :sourceInspectionIds
    WITH USER_MODE
  ]);
  candidatesById.putAll([
    SELECT Id, Name, PenaltyType__c, Status__c, Franchise__r.Name, SourceInspection__r.InspectionNo__c, CreatedDate
    FROM Penalty__c
    WHERE SourceInspection__c = NULL AND Franchise__r.Name IN :DEMO_FRANCHISES AND CreatedDate > :cutoff
    WITH USER_MODE
  ]);
} else {
  System.debug(LoggingLevel.ERROR, '>>> DEMO 점검이 없어 기준 시각을 정할 수 없음 — 페널티 후보 없음(demo-scene5-reset 먼저 실행된 적이 있는지 확인)');
}
List<Penalty__c> penalties = new List<Penalty__c>();
for (Penalty__c penalty : candidatesById.values()) {
  if (PRESERVED_PENALTIES.contains(penalty.Name)) {
    System.debug(LoggingLevel.ERROR, '>>> 보존 제외: ' + penalty.Name);
  } else {
    penalties.add(penalty);
  }
}
// NOTE: Approval.isLocked는 「Apex에서 레코드 잠금 · 잠금 해제」 설정이 꺼져 있으면 NoAccessException — 상태로 잠금을 표시한다
//       (승인대기 = 승인 진행 중 잠금, 승인 = 최종 승인 잠금 finalApprovalRecordLock)
final Set<String> LOCKED_STATUSES = new Set<String>{ '승인대기', '승인' };
Set<String> correlationIds = new Set<String>();
for (Penalty__c penalty : penalties) {
  correlationIds.add(String.valueOf(penalty.Id));
  System.debug(LoggingLevel.ERROR, '>>> 대상 페널티 ' + penalty.Name + ' · ' + penalty.PenaltyType__c + ' · ' + penalty.Status__c +
    ' · ' + penalty.Franchise__r.Name + ' · 근거 ' + penalty.SourceInspection__r.InspectionNo__c +
    (LOCKED_STATUSES.contains(penalty.Status__c) ? ' · 승인 잠금' : ''));
}

// DESC: 3) 그 페널티의 인터페이스 로그 — 페널티 조회가 이미 비었어도 상관 ID로 찾는다
List<IntegrationLog__c> logs = new List<IntegrationLog__c>();
if (!penalties.isEmpty()) {
  Set<Id> penaltyIds = new Map<Id, Penalty__c>(penalties).keySet();
  for (IntegrationLog__c log : [
    SELECT Id, Name, InterfaceId__c, Direction__c, Status__c, CorrelationId__c
    FROM IntegrationLog__c
    WHERE Penalty__c IN :penaltyIds OR CorrelationId__c IN :correlationIds
    WITH USER_MODE
  ]) {
    if (PRESERVED_LOGS.contains(log.Name)) {
      System.debug(LoggingLevel.ERROR, '>>> 보존 제외: ' + log.Name);
    } else {
      logs.add(log);
      System.debug(LoggingLevel.ERROR, '>>> 대상 로그 ' + log.Name + ' · ' + log.InterfaceId__c + ' · ' + log.Direction__c +
        ' · ' + log.Status__c);
    }
  }
}

System.debug(LoggingLevel.ERROR, '>>> 대상 합계: 페널티 ' + penalties.size() + '건 · 인터페이스 로그 ' + logs.size() + '건 · 라이브 점검 ' + liveInspections.size() + '건');
// NOTE: 물류 org 스크립트의 CORRELATION_IDS에 그대로 붙여 넣는 형태로 출력한다(org 간 조회 불가)
System.debug(LoggingLevel.ERROR, '>>> 물류 org에 넘길 상관 ID ' + correlationIds.size() + '건: ' +
  (correlationIds.isEmpty() ? '(없음)' : '\'' + String.join(new List<String>(correlationIds), '\', \'') + '\''));

if (EXECUTE && (!penalties.isEmpty() || !logs.isEmpty() || !liveInspections.isEmpty())) {
  Savepoint sp = Database.setSavepoint();
  try {
    delete logs;
    delete penalties;
    delete liveInspections;
    System.debug(LoggingLevel.ERROR, '>>> 삭제 완료: 로그 ' + logs.size() + '건 → 페널티 ' + penalties.size() + '건 → 라이브 점검 ' + liveInspections.size() + '건. 다음: 물류 org 정리 → demo-scene5-reset');
  } catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '>>> 실패 — 롤백함: ' + e.getMessage());
  }
} else if (!EXECUTE) {
  System.debug(LoggingLevel.ERROR, '>>> 미리보기라 아무것도 바꾸지 않았다. 정리하려면 EXECUTE = true');
}
