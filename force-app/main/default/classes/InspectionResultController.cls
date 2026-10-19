/* ======================================================================================
 * @description : 점검 결과 입력 화면(SC-02) — 결과 항목 조회(분류 · 템플릿 순서) · 점수 일괄 저장
 * @testClass   : InspectionResultControllerTest
 * @layer       : Controller
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 26-10-18 SC-02 점검 결과 입력 (조회 SOQL 1 · 저장 DML 1)
 *  2026.10.19   Kai        Updated     읽기 전용 조건을 「점검예정 · 점검완료가 아니면」으로 확대 — 검증 규칙 ScoreLockedAfterCompletion과 맞춤
 * ======================================================================================
 *  @see         : lwc/inspectionResultEditor, InspectionResultService.cls(미흡 판정 · 스냅샷)
 *  @note        : with sharing + USER_MODE — SV는 자기 점검만 보이고, 점수 편집 권한(FLS)이 없으면 저장이 거부된다.
 *                 미흡은 이 클래스가 아니라 결과 항목 트리거가 점수로 판정한다
 * ======================================================================================*/
public with sharing class InspectionResultController {
  // NOTE: 점수를 고칠 수 있는 상태 — 판정은 점검완료 때 정해지고, 시정 단계부터는 검증 규칙 ScoreLockedAfterCompletion이 막는다
  private static final Set<String> EDITABLE_STATUSES = new Set<String>{
    '점검예정',
    '점검완료'
  };
  // NOTE: 화면 묶음 순서 — 분류 선택 목록 정의 순서와 같다(위생 → 서비스 → 매뉴얼). 그 밖의 값은 맨 뒤
  private static final Map<String, Integer> CATEGORY_RANK = new Map<String, Integer>{
    '위생' => 0,
    '서비스' => 1,
    '매뉴얼' => 2
  };

  /**
   * @description : 결과 항목 한 줄. 정렬 키(sortOrder)는 화면에 보내지 않는다.
   **/
  public class InspectionResultWrapper implements Comparable {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String itemName;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public Decimal score;
    @AuraEnabled
    public Decimal maxScore;
    @AuraEnabled
    public Boolean isRequired;
    @AuraEnabled
    public Boolean isDeficient;
    public Decimal sortOrder;

    public Integer compareTo(Object other) {
      InspectionResultWrapper that = (InspectionResultWrapper) other;
      Integer byCategory = rankOf(category) - rankOf(that.category);
      if (byCategory != 0) {
        return byCategory;
      }
      // NOTE: 템플릿 정렬 순서가 없는 행(이관 데이터 등)은 같은 분류 안에서 뒤로, 항목명 순
      if (sortOrder != that.sortOrder) {
        if (sortOrder == null) {
          return 1;
        }
        if (that.sortOrder == null) {
          return -1;
        }
        return sortOrder < that.sortOrder ? -1 : 1;
      }
      return (itemName == null ? '' : itemName)
        .compareTo(that.itemName == null ? '' : that.itemName);
    }
  }

  /**
   * @description : 화면 한 장 — 상위 점검 상태와 결과 항목 목록.
   **/
  public class ResultSheet {
    @AuraEnabled
    public String inspectionStatus;
    @AuraEnabled
    public Boolean isReadOnly = true;
    @AuraEnabled
    public List<InspectionResultWrapper> results = new List<InspectionResultWrapper>();
  }

  /**
   * @description : 점검의 결과 항목을 분류(위생 → 서비스 → 매뉴얼) → 템플릿 정렬 순서로 돌려준다.
   *                볼 수 없는 점검 · 빈 Id면 빈 목록. 점검예정 · 점검완료가 아니거나(시정 단계부터 판정 고정) 점수 편집 권한이 없으면 읽기 전용.
   * @author      : 이은석(Kai) | 2026.10.18
   * @param inspectionId 점검 Id
   * @return ResultSheet
   **/
  @AuraEnabled(cacheable=true)
  public static ResultSheet getResults(Id inspectionId) {
    ResultSheet sheet = new ResultSheet();
    if (inspectionId == null) {
      return sheet;
    }
    // PERF: 점검 + 결과 항목을 하위 쿼리로 SOQL 1번
    List<Inspection__c> inspections = [
      SELECT
        Id,
        Status__c,
        (
          SELECT
            Id,
            ItemName__c,
            Category__c,
            Score__c,
            MaxScore__c,
            IsRequired__c,
            IsDeficient__c,
            TemplateItem__r.SortOrder__c
          FROM InspectionInspectionResults__r
        )
      FROM Inspection__c
      WHERE Id = :inspectionId
      WITH USER_MODE
    ];
    if (inspections.isEmpty()) {
      return sheet;
    }
    Inspection__c ins = inspections[0];
    sheet.inspectionStatus = ins.Status__c;
    sheet.isReadOnly =
      !EDITABLE_STATUSES.contains(ins.Status__c) ||
      !Schema.SObjectType.InspectionResult__c.fields.Score__c.isUpdateable();
    for (InspectionResult__c result : ins.InspectionInspectionResults__r) {
      InspectionResultWrapper row = new InspectionResultWrapper();
      row.id = result.Id;
      row.itemName = result.ItemName__c;
      row.category = result.Category__c;
      row.score = result.Score__c;
      row.maxScore = result.MaxScore__c;
      row.isRequired = result.IsRequired__c;
      row.isDeficient = result.IsDeficient__c;
      row.sortOrder = result.TemplateItem__r?.SortOrder__c;
      sheet.results.add(row);
    }
    sheet.results.sort();
    return sheet;
  }

  /**
   * @description : 점수만 저장한다(같은 순서의 두 목록). DML 1번. 검증 규칙 · 트리거 · 권한 오류는 메시지 그대로 화면에 돌려준다.
   * @author      : 이은석(Kai) | 2026.10.18
   * @param ids    결과 항목 Id
   * @param scores 점수(비우면 null — 미입력으로 되돌림)
   **/
  @AuraEnabled
  public static void saveResults(List<Id> ids, List<Decimal> scores) {
    if (ids == null || ids.isEmpty()) {
      return;
    }
    if (scores == null || scores.size() != ids.size()) {
      throw auraError('저장할 항목과 점수의 개수가 맞지 않습니다.');
    }
    List<InspectionResult__c> updates = new List<InspectionResult__c>();
    for (Integer i = 0; i < ids.size(); i++) {
      updates.add(new InspectionResult__c(Id = ids[i], Score__c = scores[i]));
    }
    try {
      // NOTE: USER_MODE — 점수 편집 권한(FLS) · 레코드 편집 권한이 없으면 여기서 거부된다
      update as user updates;
    } catch (DmlException e) {
      throw auraError(e.getDmlMessage(0));
    } catch (Exception e) {
      throw auraError(e.getMessage());
    }
  }

  // NOTE: AuraHandledException은 setMessage를 해야 Apex 테스트에서도 getMessage()로 같은 문구를 읽을 수 있다
  private static AuraHandledException auraError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }

  private static Integer rankOf(String category) {
    Integer rank = CATEGORY_RANK.get(category);
    return rank == null ? CATEGORY_RANK.size() : rank;
  }
}
