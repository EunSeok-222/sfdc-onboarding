/* ======================================================================================
 * @description : 점검 기준(InspectionRule__mdt) 조회 전용. 기준값 접근을 이 클래스 한 곳으로 모은다
 * @testClass   : InspectionRuleSelectorTest
 * @layer       : Selector
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.13   Kai        Created     최초 작성 — Default 기준 조회
 * ======================================================================================
 *  @see         : InspectionService.cls, customMetadata/InspectionRule.Default.md-meta.xml
 *  @note        : getInstance()는 SOQL 한도를 쓰지 않는다. 기준이 '가맹점 등급별'로 나뉘면 이 클래스만 바뀐다
 * ======================================================================================*/
public with sharing class InspectionRuleSelector {
  public static final String DEFAULT_RULE = 'Default';

  // NOTE: 테스트에서 org에 배포된 값과 무관하게 기준을 바꿔 보기 위한 주입구. 운영 코드는 쓰지 않는다
  @TestVisible
  private static InspectionRule__mdt ruleOverride;

  /**
   * @description : 기본 점검 기준을 반환한다. 레코드가 없으면 판정을 엉뚱하게 내리는 대신 즉시 실패한다.
   * @author      : 이은석(Kai) | 2026.10.13
   * @return InspectionRule__mdt Default 레코드
   **/
  public static InspectionRule__mdt getDefaultRule() {
    if (ruleOverride != null) {
      return ruleOverride;
    }
    InspectionRule__mdt rule = InspectionRule__mdt.getInstance(DEFAULT_RULE);
    if (rule == null) {
      // WARN: CMDT 레코드는 배포에 포함된다. 여기 오면 배포 누락이다 — 조용히 기본값을 쓰면 잘못된 판정이 저장된다
      throw new InspectionRuleException(
        '점검 기준(InspectionRule__mdt) \'' +
          DEFAULT_RULE +
          '\' 레코드가 없습니다. 배포 누락을 확인하세요.'
      );
    }
    return rule;
  }

  public class InspectionRuleException extends Exception {
  }
}
