/* ======================================================================================
 * @description : 기한 초과 시정조치를 '지연'으로 표시하는 배치 (BR-05). 로직은 CorrectiveActionService에 둔다
 * @testClass   : OverdueCorrectiveActionBatchTest
 * @layer       : Batch
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.12   Kai        Created     최초 작성
 * ======================================================================================
 *  @see         : CorrectiveActionService.cls, OverdueCorrectiveActionScheduler.cls
 *  @note        : 실행 사용자(스케줄 등록자) 권한으로 돈다. 스케줄은 전체 시정조치를 볼 수 있는 관리자로 등록한다
 * ======================================================================================*/
public with sharing class OverdueCorrectiveActionBatch implements Database.Batchable<sObject> {
  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT Id, Status__c, DueDate__c
        FROM CorrectiveAction__c
        WHERE
          Status__c = :CorrectiveActionService.STATUS_REQUESTED
          AND DueDate__c < TODAY
      ]
    );
  }

  public void execute(
    Database.BatchableContext bc,
    List<CorrectiveAction__c> scope
  ) {
    // NOTE: execute마다 Governor Limit이 리셋된다 — scope(기본 200건) 단위로 독립 트랜잭션
    CorrectiveActionService.markOverdue(scope);
  }

  public void finish(Database.BatchableContext bc) {
    AsyncApexJob job = [
      SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors
      FROM AsyncApexJob
      WHERE Id = :bc.getJobId()
    ];
    // WARN: JobItemsProcessed · NumberOfErrors는 레코드 수가 아니라 execute 묶음(청크) 수다.
    //       레코드 건수가 필요하면 Database.Stateful로 execute 결과를 누적해야 한다
    System.debug(
      LoggingLevel.INFO,
      'OverdueCorrectiveActionBatch 완료 · 상태 ' +
        job.Status +
        ' · 처리 청크 ' +
        job.JobItemsProcessed +
        '/' +
        job.TotalJobItems +
        ' · 실패 청크 ' +
        job.NumberOfErrors
    );
    // TODO: 지연 건 알림 발송 (담당 SV · 권역팀장) — D6 범위 밖
  }
}
