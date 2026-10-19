/* ======================================================================================
 * @description : 시연 이야기 데이터(의정부점) — 9월 정기점검 불합격 → 경고. 장면 4 「2회 연속 불합격 → 공급 제한(BR-08)」의 1회차. 기본은 미리보기
 * @layer       : Script
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 (D11 시연 장면 4 — 9월 불합격 · 경고)
 *  2026.10.19   Kai        Updated     점수 잠금 검증 규칙(ScoreLockedAfterCompletion) 영향 안내 추가 — 코드 변경 없음
 * ======================================================================================
 *  실행 : sf apex run --file scripts/apex/demo-story-uijeongbu.apex -o kai-dev
 *  순서 : 미리보기(EXECUTE = false)로 지금 값 → 바뀔 값 확인 → EXECUTE = true로 실행(끝나면 false로 되돌린다). 다시 돌려도 같은 결과
 *  WARN : 시연용 이야기 데이터 — 이관 데이터 INS-202610-0038(MIG-INS-0034)을 변경한다
 *  WARN : 26-10-19부터 시정 단계(시정중 이후) 점검의 점수는 검증 규칙 ScoreLockedAfterCompletion이 막는다.
 *         kai-dev에는 a)가 이미 반영돼 다시 돌려도 「이미 4, 건너뜀」이지만, 새 org에서 처음 돌리면 a)에서 실패하고 전체가 롤백된다
 *         (INS-0038이 처음부터 시정중이라 점수를 먼저 바꿀 수 없다) — 그때는 규칙을 잠시 끄고 돌린 뒤 다시 켠다
 *  NOTE : 하는 일
 *         a) RES-000137 냉장고 온도 관리(위생 · 필수 · 10점) 6 → 4 — 결과 항목 트리거가 미흡 판정(4 < 10 × 0.6) → 필수 미흡 1 · 23 / 40
 *         c) INS-0038 판정 불합격 · 상태 시정중 → 재점검완료 → 종료. 전이표가 한 번에 한 단계만 허용해 단계마다 update(최대 2번)
 *            판정은 점검완료일 때만 트리거가 다시 계산하므로 시정중 이후 직접 넣은 값이 유지된다
 *         d) 경고 페널티 — 의정부점 · 근거 INS-0038 · 승인 · 시작일 2026-09-26(종료일 비움) · 소유자 박 팀장
 *            승인 프로세스를 거치지 않고 insert → 승인 내역이 비어 있고 승인 잠금도 없다. 페널티 트리거는 after update만이라 insert에는 돌지 않는다
 *         e) INS-202610-0043(MIG-INS-0039 · 의정부점 10/15 점검예정 · 결과 0) 삭제 — 휴지통(복원 가능)
 *  NOTE : 시정조치는 넣지 않음 — 타임라인이 시정조치를 생성일로 그려 9월에 표시할 수 없음(2차: 업무 날짜 기준으로 변경)
 *  NOTE : 최근 정기점검일(09-24)은 바뀌지 않는다 — 재점검완료 · 종료도 집계 대상이고, 점검예정인 INS-0043은 원래 집계 대상이 아니다
 *  NOTE : demo-rehearsal-cleanup은 INS-0038과 이 경고 페널티를 보존 목록으로 제외한다
 * ======================================================================================*/
final Boolean EXECUTE = false;
final String FRANCHISE_NAME = '한끼정성 의정부점';
final String INSPECTION_NAME = 'INS-202610-0038';
final String INSPECTION_NO = 'MIG-INS-0034';
final String RESULT_NAME = 'RES-000137';
final String RESULT_ITEM = '냉장고 온도 관리';
final Decimal NEW_SCORE = 4;
final String TARGET_JUDGEMENT = '불합격';
final String PENALTY_TYPE = '경고';
final String PENALTY_STATUS = '승인';
final Date PENALTY_START_DATE = Date.newInstance(2026, 9, 26);
final String PENALTY_REASON = '위생 필수 항목 미흡 — 9월 정기점검 불합격';
final String PENALTY_OWNER_NAME = '박 팀장';
final String DELETE_INSPECTION_NAME = 'INS-202610-0043';
final String DELETE_INSPECTION_NO = 'MIG-INS-0039';

System.debug(LoggingLevel.ERROR, '>>> 모드: ' + (EXECUTE ? '실행(변경)' : '미리보기(변경 없음)'));

// DESC: 대상 확인 — 이름 · 이관번호 · 가맹점이 모두 맞을 때만 진행
Inspection__c ins = [
  SELECT Id, Name, InspectionNo__c, Status__c, Judgement__c, Franchise__c, Franchise__r.Name,
    ruTotalScore__c, ruMaxScore__c, ruDeficientRequiredCount__c
  FROM Inspection__c
  WHERE Name = :INSPECTION_NAME
];
if (ins.InspectionNo__c != INSPECTION_NO || ins.Franchise__r.Name != FRANCHISE_NAME) {
  throw new IllegalArgumentException(INSPECTION_NAME + '이 ' + INSPECTION_NO + ' · ' + FRANCHISE_NAME + '이 아닙니다: '
    + ins.InspectionNo__c + ' · ' + ins.Franchise__r.Name);
}
// WARN: 전이표 밖의 상태(점검예정 · 점검완료 · 지연 등)면 멈춘다 — 이 스크립트는 시정중 → 재점검완료 → 종료만 진행한다
if (!new Set<String>{ '시정중', '재점검완료', '종료' }.contains(ins.Status__c)) {
  throw new IllegalArgumentException(INSPECTION_NAME + ' 상태가 시정중 · 재점검완료 · 종료가 아닙니다: ' + ins.Status__c);
}
System.debug(LoggingLevel.ERROR, '>>> 지금 ' + ins.Name + ' (' + ins.InspectionNo__c + ') · ' + ins.Status__c + ' · 판정 ' + ins.Judgement__c
  + ' · ' + ins.ruTotalScore__c + ' / ' + ins.ruMaxScore__c + ' · 필수 미흡 ' + ins.ruDeficientRequiredCount__c);

InspectionResult__c result = [
  SELECT Id, Name, ItemName__c, IsRequired__c, MaxScore__c, Score__c, IsDeficient__c
  FROM InspectionResult__c
  WHERE Name = :RESULT_NAME AND Inspection__c = :ins.Id
];
if (result.ItemName__c != RESULT_ITEM || !result.IsRequired__c) {
  throw new IllegalArgumentException(RESULT_NAME + '이 필수 항목 ' + RESULT_ITEM + '이 아닙니다: ' + result.ItemName__c);
}
Boolean changeScore = result.Score__c != NEW_SCORE;
System.debug(LoggingLevel.ERROR, '>>> a) ' + result.Name + ' ' + result.ItemName__c + ' ' + result.Score__c + ' / ' + result.MaxScore__c
  + (changeScore ? ' → ' + NEW_SCORE : ' — 이미 ' + NEW_SCORE + ', 건너뜀'));

Boolean changeInspection = ins.Status__c != '종료' || ins.Judgement__c != TARGET_JUDGEMENT;
System.debug(LoggingLevel.ERROR, '>>> c) 판정 ' + ins.Judgement__c + ' → ' + TARGET_JUDGEMENT + ' · 상태 '
  + (ins.Status__c == '시정중' ? '시정중 → 재점검완료 → 종료' : ins.Status__c == '재점검완료' ? '재점검완료 → 종료' : '종료 그대로')
  + (changeInspection ? '' : ' — 이미 반영, 건너뜀'));

// DESC: 같은 근거 점검 · 같은 유형의 페널티가 이미 있으면 새로 만들지 않는다(다시 돌려도 1건)
List<Penalty__c> existingPenalties = [
  SELECT Id, Name, Status__c, StartDate__c, EndDate__c, Owner.Name
  FROM Penalty__c
  WHERE SourceInspection__c = :ins.Id AND PenaltyType__c = :PENALTY_TYPE
];
Id penaltyOwnerId = [SELECT Id FROM User WHERE Name = :PENALTY_OWNER_NAME AND IsActive = true LIMIT 1].Id;
if (existingPenalties.isEmpty()) {
  System.debug(LoggingLevel.ERROR, '>>> d) 새 페널티: ' + PENALTY_TYPE + ' · ' + PENALTY_STATUS + ' · 시작 ' + PENALTY_START_DATE
    + ' · 종료 비움 · 소유자 ' + PENALTY_OWNER_NAME + ' · 사유 「' + PENALTY_REASON + '」 (승인 프로세스 없이 insert — 승인 내역 없음)');
} else {
  for (Penalty__c existing : existingPenalties) {
    System.debug(LoggingLevel.ERROR, '>>> d) 이미 있음, 건너뜀: ' + existing.Name + ' · ' + existing.Status__c + ' · 시작 ' + existing.StartDate__c
      + ' · 소유자 ' + existing.Owner.Name);
  }
}

List<Inspection__c> deletions = [
  SELECT Id, Name, InspectionNo__c, Status__c, Franchise__r.Name, (SELECT Id FROM InspectionInspectionResults__r)
  FROM Inspection__c
  WHERE Name = :DELETE_INSPECTION_NAME
];
Set<Id> sourcedInspectionIds = new Set<Id>();
for (Penalty__c sourced : [SELECT SourceInspection__c FROM Penalty__c WHERE SourceInspection__c IN :deletions]) {
  sourcedInspectionIds.add(sourced.SourceInspection__c);
}
for (Inspection__c deletion : deletions) {
  // WARN: 이관번호 · 가맹점 · 점검예정 · 결과 0 · 근거로 쓰는 페널티 없음이 모두 맞을 때만 지운다
  if (deletion.InspectionNo__c != DELETE_INSPECTION_NO || deletion.Franchise__r.Name != FRANCHISE_NAME
      || deletion.Status__c != '점검예정' || !deletion.InspectionInspectionResults__r.isEmpty()
      || sourcedInspectionIds.contains(deletion.Id)) {
    throw new IllegalArgumentException(DELETE_INSPECTION_NAME + ' 삭제 조건이 맞지 않습니다: ' + deletion.InspectionNo__c + ' · '
      + deletion.Franchise__r.Name + ' · ' + deletion.Status__c + ' · 결과 ' + deletion.InspectionInspectionResults__r.size()
      + ' · 근거 페널티 ' + (sourcedInspectionIds.contains(deletion.Id) ? '있음' : '없음'));
  }
  System.debug(LoggingLevel.ERROR, '>>> e) 삭제(휴지통): ' + deletion.Name + ' (' + deletion.InspectionNo__c + ') · ' + deletion.Status__c + ' · 결과 0');
}
if (deletions.isEmpty()) {
  System.debug(LoggingLevel.ERROR, '>>> e) ' + DELETE_INSPECTION_NAME + ' 없음 — 이미 삭제됨, 건너뜀');
}

if (!EXECUTE) {
  System.debug(LoggingLevel.ERROR, '>>> 미리보기라 아무것도 바꾸지 않았다. 반영하려면 EXECUTE = true');
} else {
  Savepoint sp = Database.setSavepoint();
  try {
    if (changeScore) {
      update new InspectionResult__c(Id = result.Id, Score__c = NEW_SCORE);
    }
    // NOTE: 전이표(InspectionTriggerHandler)가 시정중 → 재점검완료 → 종료를 한 단계씩만 허용 — 루프 대신 단계별 update
    String status = ins.Status__c;
    if (status == '시정중') {
      update new Inspection__c(Id = ins.Id, Status__c = '재점검완료', Judgement__c = TARGET_JUDGEMENT);
      status = '재점검완료';
    }
    if (status == '재점검완료') {
      update new Inspection__c(Id = ins.Id, Status__c = '종료', Judgement__c = TARGET_JUDGEMENT);
    } else if (ins.Judgement__c != TARGET_JUDGEMENT) {
      update new Inspection__c(Id = ins.Id, Judgement__c = TARGET_JUDGEMENT);
    }
    if (existingPenalties.isEmpty()) {
      insert new Penalty__c(
        Franchise__c = ins.Franchise__c,
        SourceInspection__c = ins.Id,
        PenaltyType__c = PENALTY_TYPE,
        Status__c = PENALTY_STATUS,
        StartDate__c = PENALTY_START_DATE,
        Reason__c = PENALTY_REASON,
        OwnerId = penaltyOwnerId
      );
    }
    delete deletions;

    Inspection__c updatedIns = [
      SELECT Name, Status__c, Judgement__c, ruTotalScore__c, ruMaxScore__c, ruDeficientRequiredCount__c, Franchise__r.LastRegularInspectionDate__c
      FROM Inspection__c
      WHERE Id = :ins.Id
    ];
    System.debug(LoggingLevel.ERROR, '>>> 반영 후 ' + updatedIns.Name + ' · ' + updatedIns.Status__c + ' · 판정 ' + updatedIns.Judgement__c + ' · '
      + updatedIns.ruTotalScore__c + ' / ' + updatedIns.ruMaxScore__c + ' · 필수 미흡 ' + updatedIns.ruDeficientRequiredCount__c
      + ' · 가맹점 최근 정기점검일 ' + updatedIns.Franchise__r.LastRegularInspectionDate__c);
    for (Penalty__c penalty : [
      SELECT Name, PenaltyType__c, Status__c, StartDate__c, EndDate__c, Owner.Name
      FROM Penalty__c
      WHERE SourceInspection__c = :ins.Id AND PenaltyType__c = :PENALTY_TYPE
    ]) {
      System.debug(LoggingLevel.ERROR, '>>> 반영 후 페널티 ' + penalty.Name + ' · ' + penalty.PenaltyType__c + ' · ' + penalty.Status__c
        + ' · 시작 ' + penalty.StartDate__c + ' · 종료 ' + penalty.EndDate__c + ' · 소유자 ' + penalty.Owner.Name
        + ' — demo-rehearsal-cleanup 보존 목록에 이 번호를 넣는다');
    }
  } catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '>>> 실패 — 롤백함: ' + e.getMessage());
  }
}
