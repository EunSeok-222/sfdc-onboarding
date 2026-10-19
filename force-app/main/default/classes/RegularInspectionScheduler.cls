/* ======================================================================================
 * @description : 다음 정기점검 자동 생성 스케줄러 — 매일 06:00 RegularInspectionBatch 실행
 * @testClass   : RegularInspectionScheduleServiceTest
 * @layer       : Batch
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성
 * ======================================================================================
 *  @note        : 등록(관리자, 시점은 Kai가 정한다 — 시연 데이터 보호) —
 *                 System.schedule('정기점검 자동 생성', RegularInspectionScheduler.CRON_DAILY_6AM,
 *                 new RegularInspectionScheduler());  (초 분 시 일 월 요일 → 매일 06:00)
 * ======================================================================================*/
public with sharing class RegularInspectionScheduler implements Schedulable {
  public static final String CRON_DAILY_6AM = '0 0 6 * * ?';

  public void execute(SchedulableContext sc) {
    Database.executeBatch(
      new RegularInspectionBatch(),
      RegularInspectionBatch.BATCH_SIZE
    );
  }
}
