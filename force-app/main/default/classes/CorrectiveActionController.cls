/* ======================================================================================
 * @description : 점검 1건에 달린 시정조치 목록 조회 컨트롤러 (점검 상세 화면의 시정조치 목록)
 * @testClass   : CorrectiveActionControllerTest
 * @layer       : Controller
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 (D8 자식→부모 이벤트 실습의 목록 조회)
 *  2026.10.14   Kai        Updated     getDeficientResults 추가 (시정조치 추가 폼의 미흡 항목 선택지)
 * ======================================================================================
 *  @see         : InspectionListController.cls
 *  @note        : 시정조치 생성 · 수정은 LDS(lightning-record-edit-form)가 맡는다. 이 클래스는 조회만 한다
 * ======================================================================================*/
public with sharing class CorrectiveActionController {
  /**
   * @description : 점검에 달린 시정조치를 기한 오름차순으로 돌려준다.
   * @author      : 이은석(Kai) | 2026.10.14
   * @param inspectionId 점검 Id (null이면 빈 목록)
   * @return List<CorrectiveAction__c> 결과 항목의 항목명 · 필수 여부를 포함한 시정조치
   **/
  @AuraEnabled(cacheable=true)
  public static List<CorrectiveAction__c> getByInspection(Id inspectionId) {
    // NOTE: 화면이 recordId 없이 불러도 에러 Toast 대신 빈 목록을 보여 주도록 예외를 던지지 않는다
    if (inspectionId == null) {
      return new List<CorrectiveAction__c>();
    }

    // DESC: 시정조치 → 결과 항목(M-D) → 점검(M-D) 관계를 타고 점검 기준으로 거른다. SOQL 1번
    // DESC: WITH USER_MODE — with sharing은 '어떤 레코드(행)를 보나'만 거르고, 오브젝트 · 필드 권한(FLS)은 별도다.
    //       USER_MODE는 현재 사용자의 오브젝트 · 필드 권한까지 강제해, 읽을 수 없는 필드가 섞이면 조회 자체를 막는다
    // NOTE: 기한이 같은 행끼리는 순서가 보장되지 않는다. Name(자동 번호)으로 2차 정렬해 화면 순서를 고정한다
    //       (InspectionListController의 Name 2차 정렬과 같은 이유)
    return [
      SELECT
        Id,
        Name,
        Status__c,
        DueDate__c,
        RequiresRevisit__c,
        InspectionResult__c,
        InspectionResult__r.ItemName__c,
        InspectionResult__r.IsRequired__c
      FROM CorrectiveAction__c
      WHERE InspectionResult__r.Inspection__c = :inspectionId
      WITH USER_MODE
      ORDER BY DueDate__c ASC NULLS LAST, Name ASC
    ];
  }

  /**
   * @description : 점검의 미흡 결과 항목을 돌려준다. 시정조치를 어느 항목에 달지 고르는 선택지로 쓴다.
   * @author      : 이은석(Kai) | 2026.10.14
   * @param inspectionId 점검 Id (null이면 빈 목록)
   * @return List<InspectionResult__c> 미흡(IsDeficient__c = true) 결과 항목
   **/
  @AuraEnabled(cacheable=true)
  public static List<InspectionResult__c> getDeficientResults(Id inspectionId) {
    if (inspectionId == null) {
      return new List<InspectionResult__c>();
    }

    // DESC: WITH USER_MODE — getByInspection과 같은 이유 (sharing은 행만, FLS는 별도)
    // NOTE: IsRequired__c DESC — BR-03: 필수 항목 미흡은 총점과 무관하게 불합격이라 가장 먼저 조치해야 한다.
    //       선택 목록 맨 위에 와야 SV가 놓치지 않는다
    // NOTE: Category__c는 선택 목록이라 가나다순이 아니라 선택 목록 정의 순서(위생 → 서비스 → 매뉴얼)로 정렬된다
    return [
      SELECT Id, ItemName__c, Category__c, IsRequired__c
      FROM InspectionResult__c
      WHERE Inspection__c = :inspectionId AND IsDeficient__c = TRUE
      WITH USER_MODE
      ORDER BY IsRequired__c DESC, Category__c, ItemName__c
    ];
  }
}
