/* ======================================================================================
 * @description : OverdueCorrectiveActionBatch를 정해진 시각에 실행하는 스케줄러. 실행만 책임진다
 * @testClass   : OverdueCorrectiveActionBatchTest
 * @layer       : Scheduler
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.12   Kai        Created     최초 작성
 * ======================================================================================
 *  @note        : 등록 예 — System.schedule('한끼정성 기한초과 시정조치', '0 0 1 * * ?',
 *                 new OverdueCorrectiveActionScheduler());  (초 분 시 일 월 요일 → 매일 01:00)
 * ======================================================================================*/
public with sharing class OverdueCorrectiveActionScheduler implements Schedulable {
  public void execute(SchedulableContext sc) {
    Database.executeBatch(new OverdueCorrectiveActionBatch(), 200);
  }
}
