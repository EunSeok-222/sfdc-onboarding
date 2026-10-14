/* ======================================================================================
 * @description : 기한 초과 시정조치 지연 표시 배치 · 스케줄러를 검증하는 테스트 클래스 (BR-05)
 * @testTarget  : OverdueCorrectiveActionBatch, OverdueCorrectiveActionScheduler, CorrectiveActionService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.12   Kai        Created     최초 작성
 * ======================================================================================
 *  @note        : 배치는 Test.stopTest() 시점에 동기 실행된다. Assert는 반드시 stopTest() 뒤에 둔다
 * ======================================================================================*/
@IsTest
private class OverdueCorrectiveActionBatchTest {
  private static final Integer OVERDUE_COUNT = 5;
  private static final Integer NOT_DUE_COUNT = 3;

  @TestSetup
  static void setupData() {
    Account franchise = TestDataFactory.createFranchises(1, true)[0];
    Inspection__c ins = TestDataFactory.createInspections(
      new List<Account>{ franchise },
      1,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    )[0];
    List<InspectionTemplateItem__c> items = TestDataFactory.createTemplateItems(
      1,
      0,
      10,
      true
    );
    List<InspectionResult__c> results = TestDataFactory.createResults(
      ins,
      items,
      new List<Decimal>{ 5 },
      true
    );

    Date today = Date.today();
    List<CorrectiveAction__c> actions = new List<CorrectiveAction__c>();
    // DESC: 기한 지난 '요청' 5건 — 지연 대상
    actions.addAll(
      TestDataFactory.createCorrectiveActions(
        results,
        OVERDUE_COUNT,
        CorrectiveActionService.STATUS_REQUESTED,
        today.addDays(-1),
        false
      )
    );
    // DESC: 기한 내 '요청' 3건 — 오늘이 기한인 1건(경계값: DueDate < TODAY가 아님) + 내일이 기한인 2건
    actions.addAll(
      TestDataFactory.createCorrectiveActions(
        results,
        1,
        CorrectiveActionService.STATUS_REQUESTED,
        today,
        false
      )
    );
    actions.addAll(
      TestDataFactory.createCorrectiveActions(
        results,
        NOT_DUE_COUNT - 1,
        CorrectiveActionService.STATUS_REQUESTED,
        today.addDays(1),
        false
      )
    );
    insert actions; // DML 1번
  }

  // 배치 실행 → 기한 지난 5건만 지연, 기한 내 3건(오늘 기한 포함)은 요청 유지
  @IsTest
  static void batch_overdueRequested_markedOverdue() {
    Test.startTest();
    Database.executeBatch(new OverdueCorrectiveActionBatch(), 200);
    Test.stopTest(); // NOTE: 여기서 배치가 동기적으로 실행된다

    assertStatusCounts();
  }

  // 스케줄러 실행 → 배치를 호출해 같은 결과
  @IsTest
  static void scheduler_execute_runsBatch() {
    Test.startTest();
    // NOTE: execute를 직접 호출하면 스케줄러가 넣은 배치가 stopTest()에서 실행된다 (SchedulableContext는 쓰지 않으므로 null)
    new OverdueCorrectiveActionScheduler().execute(null);
    Test.stopTest();

    assertStatusCounts();
  }

  private static void assertStatusCounts() {
    Assert.areEqual(
      OVERDUE_COUNT,
      [
        SELECT COUNT()
        FROM CorrectiveAction__c
        WHERE Status__c = :CorrectiveActionService.STATUS_OVERDUE
      ],
      '기한이 지난 요청 시정조치 5건은 지연으로 바뀌어야 한다 (BR-05)'
    );
    Assert.areEqual(
      NOT_DUE_COUNT,
      [
        SELECT COUNT()
        FROM CorrectiveAction__c
        WHERE Status__c = :CorrectiveActionService.STATUS_REQUESTED
      ],
      '기한 내 시정조치 3건은 요청으로 남아야 한다. 오늘이 기한인 건도 지연이 아니다 (DueDate < TODAY)'
    );
  }
}
