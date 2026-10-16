/* ======================================================================================
 * @description : 매장 이력 타임라인(SC-03) 조회 컨트롤러 — 가맹점의 점검 · 시정조치 · 페널티를 시간순으로 돌려준다
 * @testClass   : FranchiseHistoryControllerTest
 * @layer       : Controller
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 (유형별 SOQL 3번 · 최근 12개월 · 날짜 내림차순)
 * ======================================================================================
 *  @see         : franchiseHistoryTimeline (LWC), docs/design/sc03-franchise-history-mockup.html
 *  @note        : 데이터만 돌려준다. 문구 조합 · 색 결정은 LWC가 한다 — 같은 데이터를 다른 화면이 다르게 보여 줄 수 있게
 * ======================================================================================*/
public with sharing class FranchiseHistoryController {
  public static final String TYPE_INSPECTION = 'INSPECTION';
  public static final String TYPE_ACTION = 'ACTION';
  public static final String TYPE_PENALTY = 'PENALTY';

  // NOTE: 요건 SC-03 「최근 12개월」. 정기점검이 월 1회(BR-01)라 1년이면 같은 달 작년 결과와 비교할 수 있고,
  //       BR-08 연속 지적 · 연속 불합격 판단에 필요한 기간을 넉넉히 덮는다. 기간이 무한하면 오래된 매장일수록 화면과 쿼리가 커진다
  public static final Integer LOOKBACK_MONTHS = 12;

  /**
   * @description : 타임라인 한 줄. 유형과 무관한 공통 필드 + 유형별 필드(해당 없으면 null)
   * @note        : Comparable — 세 유형을 한 목록으로 합친 뒤 정렬한다. SOQL ORDER BY는 쿼리마다 따로라
   *                유형을 섞은 순서는 Apex에서만 정할 수 있다
   **/
  public class HistoryEventWrapper implements Comparable {
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public String recordNo;
    @AuraEnabled
    public String eventType; // INSPECTION | ACTION | PENALTY
    @AuraEnabled
    public Date eventDate;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String status;

    // DESC: 점검
    @AuraEnabled
    public String judgement;
    @AuraEnabled
    public Decimal score;
    @AuraEnabled
    public Decimal maxScore;
    @AuraEnabled
    public Decimal requiredDeficientCount;
    // NOTE: 합격선(InspectionRule__mdt) — 화면의 점수 바 마커 위치. LDS는 Custom Metadata를 못 읽어 Apex가 함께 내려준다
    @AuraEnabled
    public Decimal passRate;

    // DESC: 시정조치
    @AuraEnabled
    public String itemName;
    @AuraEnabled
    public Boolean isRequired;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Date completedDate;
    @AuraEnabled
    public Boolean requiresRevisit;

    // DESC: 페널티
    @AuraEnabled
    public String penaltyType;
    @AuraEnabled
    public String reason;
    @AuraEnabled
    public String sourceInspectionNo;

    // NOTE: 날짜 내림차순 → 같은 날이면 생성 시각 내림차순(늦게 생긴 일이 위) → 그래도 같으면 번호 내림차순으로 순서를 고정한다.
    //       날짜만 보면 같은 날 생긴 점검 · 시정조치 · 페널티의 순서가 조회 때마다 바뀔 수 있다
    public Integer compareTo(Object other) {
      HistoryEventWrapper that = (HistoryEventWrapper) other;
      Integer byDate = compareDesc(eventDate, that.eventDate);
      if (byDate != 0) {
        return byDate;
      }
      Integer byCreated = compareDesc(createdDate, that.createdDate);
      if (byCreated != 0) {
        return byCreated;
      }
      return compareDesc(recordNo, that.recordNo);
    }
  }

  /**
   * @description : 가맹점의 최근 12개월 점검 · 시정조치 · 페널티를 날짜 내림차순으로 돌려준다.
   * @author      : 이은석(Kai) | 2026.10.14
   * @param franchiseId 가맹점(Account) Id (null이면 빈 목록)
   * @return List<HistoryEventWrapper> 세 유형을 합쳐 정렬한 이벤트
   **/
  @AuraEnabled(cacheable=true)
  public static List<HistoryEventWrapper> getHistory(Id franchiseId) {
    List<HistoryEventWrapper> events = new List<HistoryEventWrapper>();
    if (franchiseId == null) {
      return events;
    }
    Date sinceDate = Date.today().addMonths(-LOOKBACK_MONTHS);
    // NOTE: CreatedDate는 Datetime이라 기준일 0시(실행 사용자 시간대)로 맞춰 비교한다
    Datetime sinceDatetime = Datetime.newInstance(
      sinceDate,
      Time.newInstance(0, 0, 0, 0)
    );

    // DESC: SOQL은 유형별 1번씩 3번. 세 쿼리 모두 WITH USER_MODE — with sharing은 행만 거르고 FLS는 별도다
    events.addAll(toInspectionEvents(franchiseId, sinceDate));
    events.addAll(toActionEvents(franchiseId, sinceDatetime));
    events.addAll(toPenaltyEvents(franchiseId, sinceDate, sinceDatetime));
    events.sort();
    return events;
  }

  private static List<HistoryEventWrapper> toInspectionEvents(
    Id franchiseId,
    Date sinceDate
  ) {
    List<HistoryEventWrapper> events = new List<HistoryEventWrapper>();
    // PERF: Custom Metadata getInstance는 SOQL 한도를 쓰지 않는다
    Decimal passRate = InspectionRuleSelector.getDefaultRule().PassRate__c;
    for (Inspection__c ins : [
      SELECT
        Id,
        Name,
        InspectionDate__c,
        CreatedDate,
        Status__c,
        Judgement__c,
        RecordType.Name,
        ruTotalScore__c,
        ruMaxScore__c,
        ruDeficientRequiredCount__c
      FROM Inspection__c
      WHERE Franchise__c = :franchiseId AND InspectionDate__c >= :sinceDate
      WITH USER_MODE
    ]) {
      HistoryEventWrapper event = newEvent(
        ins.Id,
        ins.Name,
        TYPE_INSPECTION,
        ins.InspectionDate__c,
        ins.CreatedDate
      );
      event.title = ins.RecordType.Name;
      event.status = ins.Status__c;
      event.judgement = ins.Judgement__c;
      event.score = ins.ruTotalScore__c;
      event.maxScore = ins.ruMaxScore__c;
      event.requiredDeficientCount = ins.ruDeficientRequiredCount__c;
      event.passRate = passRate;
      events.add(event);
    }
    return events;
  }

  private static List<HistoryEventWrapper> toActionEvents(
    Id franchiseId,
    Datetime sinceDatetime
  ) {
    List<HistoryEventWrapper> events = new List<HistoryEventWrapper>();
    // NOTE: 시정조치는 결과 항목 → 점검 → 가맹점 2단 관계로 거른다. 기준일은 요청일(생성일)이다
    for (CorrectiveAction__c action : [
      SELECT
        Id,
        Name,
        Status__c,
        DueDate__c,
        CompletedDate__c,
        RequiresRevisit__c,
        CreatedDate,
        InspectionResult__r.ItemName__c,
        InspectionResult__r.IsRequired__c
      FROM CorrectiveAction__c
      WHERE
        InspectionResult__r.Inspection__r.Franchise__c = :franchiseId
        AND CreatedDate >= :sinceDatetime
      WITH USER_MODE
    ]) {
      HistoryEventWrapper event = newEvent(
        action.Id,
        action.Name,
        TYPE_ACTION,
        action.CreatedDate.date(),
        action.CreatedDate
      );
      event.title = action.InspectionResult__r.ItemName__c;
      event.status = action.Status__c;
      event.itemName = action.InspectionResult__r.ItemName__c;
      event.isRequired = action.InspectionResult__r.IsRequired__c;
      event.dueDate = action.DueDate__c;
      event.completedDate = action.CompletedDate__c;
      event.requiresRevisit = action.RequiresRevisit__c;
      events.add(event);
    }
    return events;
  }

  private static List<HistoryEventWrapper> toPenaltyEvents(
    Id franchiseId,
    Date sinceDate,
    Datetime sinceDatetime
  ) {
    List<HistoryEventWrapper> events = new List<HistoryEventWrapper>();
    // NOTE: 승인 대기 페널티는 시작일이 아직 정해지지 않아 비어 있을 수 있다(승인 후 제한 기간을 정한다).
    //       그런 페널티도 타임라인에서 빠지면 안 되므로 시작일이 없으면 생성일을 기준일로 쓴다
    for (Penalty__c penalty : [
      SELECT
        Id,
        Name,
        PenaltyType__c,
        Status__c,
        StartDate__c,
        EndDate__c,
        Reason__c,
        CreatedDate,
        SourceInspection__r.Name
      FROM Penalty__c
      WHERE
        Franchise__c = :franchiseId
        AND (StartDate__c >= :sinceDate
        OR (StartDate__c = NULL
        AND CreatedDate >= :sinceDatetime))
      WITH USER_MODE
    ]) {
      HistoryEventWrapper event = newEvent(
        penalty.Id,
        penalty.Name,
        TYPE_PENALTY,
        penalty.StartDate__c != null
          ? penalty.StartDate__c
          : penalty.CreatedDate.date(),
        penalty.CreatedDate
      );
      event.title = penalty.PenaltyType__c;
      event.status = penalty.Status__c;
      event.penaltyType = penalty.PenaltyType__c;
      event.reason = penalty.Reason__c;
      event.sourceInspectionNo = penalty.SourceInspection__r?.Name;
      events.add(event);
    }
    return events;
  }

  private static HistoryEventWrapper newEvent(
    Id recordId,
    String recordNo,
    String eventType,
    Date eventDate,
    Datetime createdDate
  ) {
    HistoryEventWrapper event = new HistoryEventWrapper();
    event.recordId = recordId;
    event.recordNo = recordNo;
    event.eventType = eventType;
    event.eventDate = eventDate;
    event.createdDate = createdDate;
    return event;
  }

  // DESC: 내림차순 비교. null은 맨 뒤로 보낸다
  private static Integer compareDesc(Object left, Object right) {
    if (left == right) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    if (left instanceof Date) {
      return (Date) left > (Date) right ? -1 : 1;
    }
    if (left instanceof Datetime) {
      return (Datetime) left > (Datetime) right ? -1 : 1;
    }
    return (String) left > (String) right ? -1 : 1;
  }
}
