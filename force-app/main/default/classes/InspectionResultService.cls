/* ======================================================================================
 * @description : 점검 결과 항목 비즈니스 로직 — 템플릿 스냅샷 복사(BR-11) · 항목 미흡 판정(BR-03)
 * @testClass   : InspectionResultTriggerHandlerTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 스냅샷 복사(SOQL 1회) · 미흡 = 점수 < 배점 × 항목 미흡 기준(D1)
 * ======================================================================================
 *  @see         : InspectionResultTriggerHandler.cls, InspectionRuleSelector.cls, 요건 정의서 V1.1 BR-03 · BR-11
 *  @note        : 미흡(IsDeficient__c)은 Roll-Up ruDeficientRequiredCount__c(필수 · 미흡 건수)의 입력이다 —
 *                 필수 미흡이 1건이라도 있으면 총점과 무관하게 불합격(InspectionService)
 * ======================================================================================*/
public with sharing class InspectionResultService {
  /**
   * @description : 템플릿이 지정된 결과 항목에 항목명 · 분류 · 배점 · 필수를 복사한다(insert 전용).
   *                템플릿이 없는 결과는 입력값 그대로 둔다(이관 · 테스트 데이터).
   * @author      : 이은석(Kai) | 2026.10.18
   * @param results Trigger.new (before insert — DML 없이 값만 바꾼다)
   **/
  public static void copyTemplateSnapshots(List<InspectionResult__c> results) {
    Set<Id> templateIds = new Set<Id>();
    for (InspectionResult__c result : results) {
      if (result.TemplateItem__c != null) {
        templateIds.add(result.TemplateItem__c);
      }
    }
    if (templateIds.isEmpty()) {
      return;
    }
    // PERF: 건수와 무관하게 SOQL 1번
    // NOTE: 템플릿은 전사 공개 참조 데이터(OWD 읽기 전용)다. 스냅샷 복사는 사용자 행위가 아니라 시스템 규칙(BR-11)이라
    //       실행 사용자의 템플릿 필드 FLS와 무관하게 시스템 모드로 읽는다
    Map<Id, InspectionTemplateItem__c> templatesById = new Map<Id, InspectionTemplateItem__c>(
      [
        SELECT Id, Name, Category__c, MaxScore__c, IsRequired__c
        FROM InspectionTemplateItem__c
        WHERE Id IN :templateIds
        WITH SYSTEM_MODE
      ]
    );
    for (InspectionResult__c result : results) {
      InspectionTemplateItem__c template = templatesById.get(
        result.TemplateItem__c
      );
      if (template != null) {
        result.ItemName__c = template.Name;
        result.Category__c = template.Category__c;
        result.MaxScore__c = template.MaxScore__c;
        result.IsRequired__c = template.IsRequired__c;
      }
    }
  }

  /**
   * @description : 미흡을 판정한다. 점수 < 배점 × 항목 미흡 기준이면 미흡, 점수나 배점이 비면 판정 보류(false).
   * @author      : 이은석(Kai) | 2026.10.18
   * @param results Trigger.new (before insert · update — DML 없이 값만 바꾼다)
   **/
  public static void applyDeficiency(List<InspectionResult__c> results) {
    Decimal rate = InspectionRuleSelector.getDeficiencyRate();
    for (InspectionResult__c result : results) {
      // NOTE: 사람이 입력한 미흡 값은 쓰지 않는다 — 저장할 때마다 점수로 다시 계산한다(화면에서는 읽기 전용)
      result.IsDeficient__c =
        result.Score__c != null &&
        result.MaxScore__c != null &&
        result.Score__c < result.MaxScore__c * rate;
    }
  }
}
