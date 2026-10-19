/* ======================================================================================
 * @description : 다음 정기점검 자동 생성(BR-01) — 활성 가맹점마다 점검예정 정기점검이 없으면 1건 만든다
 * @testClass   : RegularInspectionScheduleServiceTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.19   Kai        Created     최초 작성 — 점검일 계산(월 1회 · 신규 매장 15일) · 소유자(비활성이면 미배정 큐)
 * ======================================================================================
 *  @see         : RegularInspectionBatch.cls, RegularInspectionScheduler.cls, InspectionTriggerHandler(결과 항목 20행 자동 생성)
 *  @note        : 활성 가맹점 = 매장코드가 있고 Active__c가 No가 아닌 Account. 26-10-19 기준 가맹점 34곳 모두 Active__c가 비어 있어
 *                 「Yes만」으로 고르면 한 곳도 잡히지 않는다 — 명시적으로 No인 곳만 뺀다
 * ======================================================================================*/
public with sharing class RegularInspectionScheduleService {
  public static final String REGULAR_RECORD_TYPE = 'Regular';
  public static final String SCHEDULED_STATUS = '점검예정';
  public static final String INACTIVE_FRANCHISE = 'No';
  public static final String UNASSIGNED_QUEUE = 'UnassignedInspection';

  // NOTE: BR-01 — 정기점검은 월 1회, 오픈 3개월 이내 신규 매장은 15일 간격
  private static final Integer REGULAR_INTERVAL_MONTHS = 1;
  private static final Integer NEW_STORE_MONTHS = 3;
  private static final Integer NEW_STORE_INTERVAL_DAYS = 15;

  private static final Id REGULAR_RECORD_TYPE_ID = Schema.SObjectType.Inspection__c
    .getRecordTypeInfosByDeveloperName()
    .get(REGULAR_RECORD_TYPE)
    .getRecordTypeId();

  /**
   * @description : 배치 start용 — 활성 가맹점(매장코드 있음 · Active__c ≠ No). franchiseIds가 있으면 그 가맹점만.
   * @author      : 이은석(Kai) | 2026.10.19
   * @param franchiseIds 대상 가맹점 Id(null이면 전체 — 스모크는 1곳만 넘긴다)
   * @return Database.QueryLocator
   **/
  public static Database.QueryLocator activeFranchiseLocator(
    Set<Id> franchiseIds
  ) {
    if (franchiseIds == null) {
      return Database.getQueryLocator(
        [
          SELECT
            Id,
            Name,
            OwnerId,
            Owner.IsActive,
            OpenDate__c,
            LastRegularInspectionDate__c,
            StoreCode__c,
            Active__c
          FROM Account
          WHERE StoreCode__c != NULL AND Active__c != :INACTIVE_FRANCHISE
        ]
      );
    }
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Name,
          OwnerId,
          Owner.IsActive,
          OpenDate__c,
          LastRegularInspectionDate__c,
          StoreCode__c,
          Active__c
        FROM Account
        WHERE
          Id IN :franchiseIds
          AND StoreCode__c != NULL
          AND Active__c != :INACTIVE_FRANCHISE
      ]
    );
  }

  /**
   * @description : 가맹점마다 다음 정기점검(점검예정)을 1건 만든다. 점검예정 정기점검이 이미 있으면 건너뛴다(다시 돌려도 중복 없음).
   *                소유자 = 가맹점 소유자, 비활성이면 미배정 점검 큐. 결과 항목 20행은 점검 트리거(after insert)가 만든다.
   * @author      : 이은석(Kai) | 2026.10.19
   * @param franchises Id · OwnerId · Owner.IsActive · OpenDate__c · LastRegularInspectionDate__c · StoreCode__c · Active__c
   * @return List<Inspection__c> 새로 만든 점검
   **/
  public static List<Inspection__c> createNextInspections(
    List<Account> franchises
  ) {
    List<Account> targets = new List<Account>();
    for (Account franchise : franchises) {
      // NOTE: 호출자가 아무 목록이나 넘겨도 활성 가맹점만 — 배치 쿼리와 같은 기준
      if (
        String.isNotBlank(franchise.StoreCode__c) &&
        franchise.Active__c != INACTIVE_FRANCHISE
      ) {
        targets.add(franchise);
      }
    }
    if (targets.isEmpty()) {
      return new List<Inspection__c>();
    }

    Set<Id> scheduledFranchiseIds = findFranchisesWithScheduledInspection(
      new Map<Id, Account>(targets).keySet()
    );
    Date today = Date.today();
    Id queueId;
    List<Inspection__c> inspections = new List<Inspection__c>();
    for (Account franchise : targets) {
      if (scheduledFranchiseIds.contains(franchise.Id)) {
        continue; // DESC: 진행 중인 정기점검(점검예정)이 있으면 그 점검을 먼저 끝내야 한다
      }
      Id ownerId = franchise.OwnerId;
      if (franchise.Owner?.IsActive != true) {
        // PERF: 큐 Id는 비활성 소유자가 있을 때만, 트랜잭션당 1번 조회
        queueId = queueId != null ? queueId : getUnassignedQueueId();
        ownerId = queueId;
      }
      inspections.add(
        new Inspection__c(
          Franchise__c = franchise.Id,
          RecordTypeId = REGULAR_RECORD_TYPE_ID,
          Status__c = SCHEDULED_STATUS,
          InspectionDate__c = nextInspectionDate(
            franchise.LastRegularInspectionDate__c,
            franchise.OpenDate__c,
            today
          ),
          OwnerId = ownerId
        )
      );
    }
    if (!inspections.isEmpty()) {
      insert inspections; // DML 1번 — 결과 항목은 점검 트리거가 일괄로 만든다
    }
    return inspections;
  }

  /**
   * @description : 다음 정기점검일 — (최근 정기점검일, 없으면 오픈일) + 1개월(오픈 3개월 이내면 + 15일).
   *                기준일이 없거나 계산일이 오늘보다 이르면 오늘.
   * @author      : 이은석(Kai) | 2026.10.19
   * @param lastInspection 최근 정기점검일(Account.LastRegularInspectionDate__c)
   * @param openDate       오픈일(Account.OpenDate__c)
   * @param today          기준일(테스트에서 고정하려고 인자로 받는다)
   * @return Date 점검일
   **/
  public static Date nextInspectionDate(
    Date lastInspection,
    Date openDate,
    Date today
  ) {
    Date base = lastInspection != null ? lastInspection : openDate;
    if (base == null) {
      return today;
    }
    Boolean isNewStore =
      openDate != null &&
      openDate >= today.addMonths(-NEW_STORE_MONTHS);
    Date next = isNewStore
      ? base.addDays(NEW_STORE_INTERVAL_DAYS)
      : base.addMonths(REGULAR_INTERVAL_MONTHS);
    return next < today ? today : next;
  }

  private static Set<Id> findFranchisesWithScheduledInspection(
    Set<Id> franchiseIds
  ) {
    Set<Id> scheduledFranchiseIds = new Set<Id>();
    // NOTE: SYSTEM_MODE — 실행자(스케줄 등록 관리자)가 아닌 사람이 돌려도 다른 SV 소유 점검예정을 놓치면 중복 생성된다
    for (Inspection__c ins : [
      SELECT Franchise__c
      FROM Inspection__c
      WHERE
        Franchise__c IN :franchiseIds
        AND RecordTypeId = :REGULAR_RECORD_TYPE_ID
        AND Status__c = :SCHEDULED_STATUS
      WITH SYSTEM_MODE
    ]) {
      scheduledFranchiseIds.add(ins.Franchise__c);
    }
    return scheduledFranchiseIds;
  }

  private static Id getUnassignedQueueId() {
    List<Group> queues = [
      SELECT Id
      FROM Group
      WHERE Type = 'Queue' AND DeveloperName = :UNASSIGNED_QUEUE
      LIMIT 1
    ];
    if (queues.isEmpty()) {
      // WARN: 큐가 없으면 비활성 사용자에게 배정하려다 INACTIVE_OWNER_OR_USER로 묶음 전체가 실패한다 — 원인을 바로 알린다
      throw new RegularInspectionException(
        '미배정 점검 큐(' + UNASSIGNED_QUEUE + ')가 없습니다.'
      );
    }
    return queues[0].Id;
  }

  public class RegularInspectionException extends Exception {
  }
}
