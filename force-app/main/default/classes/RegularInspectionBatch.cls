/* ======================================================================================
 * @description : 다음 정기점검 자동 생성 배치(BR-01) — 활성 가맹점을 50곳씩 RegularInspectionScheduleService에 넘긴다
 * @testClass   : RegularInspectionScheduleServiceTest
 * @layer       : Batch
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — 가맹점 Id 지정 생성자(스모크 1곳) · 배치 크기 50
 * ======================================================================================
 *  @see         : RegularInspectionScheduleService.cls, RegularInspectionScheduler.cls
 *  @note        : 실행 사용자(스케줄 등록자) 권한으로 돈다 — 전체 가맹점을 볼 수 있는 관리자로 등록한다.
 *                 크기 50 = 점검 50건 × 결과 항목 20행 = 1,000행 insert가 한 묶음
 * ======================================================================================*/
public with sharing class RegularInspectionBatch implements Database.Batchable<sObject> {
  public static final Integer BATCH_SIZE = 50;

  // DESC: null이면 활성 가맹점 전체, 값이 있으면 그 가맹점만(스모크 · 수동 재실행)
  private final Set<Id> franchiseIds;

  public RegularInspectionBatch() {
    this(null);
  }

  public RegularInspectionBatch(Set<Id> franchiseIds) {
    this.franchiseIds = franchiseIds;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return RegularInspectionScheduleService.activeFranchiseLocator(
      franchiseIds
    );
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    RegularInspectionScheduleService.createNextInspections(scope);
  }

  public void finish(Database.BatchableContext bc) {
    System.debug(
      LoggingLevel.INFO,
      'RegularInspectionBatch 완료 · Job ' + bc.getJobId()
    );
  }
}
