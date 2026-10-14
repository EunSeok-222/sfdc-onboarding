/* ======================================================================================
 * @description : InspectionService 단위 테스트 — 판정 계산(BR-02 · BR-03) 경계값 중심
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.12   Kai        Created     최초 작성 — applyJudgements 경계값
 *  2026.10.12   Kai        Updated     메서드명 축약 (Apex 식별자는 ASCII만 허용 — 설명은 주석으로)
 * ======================================================================================
 *  @see         : InspectionService.cls, docs/d6-test-scenarios.md
 *  @note        : applyJudgements는 SOQL · DML이 없어 레코드를 insert하지 않고 검증한다.
 *                 Roll-Up은 생성자로 대입 불가. JSON 역직렬화로 값을 주입한다
 * ======================================================================================*/
@IsTest
private class InspectionServiceTest {
  private static Inspection__c newScoredInspection(
    Decimal totalScore,
    Decimal maxScore,
    Decimal deficientRequiredCount
  ) {
    // NOTE: Roll-Up Summary는 생성자로 대입 불가(Field is not writeable).
    //       JSON 역직렬화는 쓰기 가능 여부를 검사하지 않아 테스트 값 주입에 쓴다.
    Map<String, Object> fieldValues = new Map<String, Object>{
      'ruTotalScore__c' => totalScore,
      'ruMaxScore__c' => maxScore,
      'ruDeficientRequiredCount__c' => deficientRequiredCount
    };
    return (Inspection__c) JSON.deserialize(
      JSON.serialize(fieldValues),
      Inspection__c.class
    );
  }

  private static String judgementOf(Inspection__c ins) {
    InspectionService.applyJudgements(new List<Inspection__c>{ ins });
    return ins.Judgement__c;
  }

  // S-01 득점률 0.8(합격선과 같음) → 합격
  @IsTest
  static void rate80_pass() {
    Inspection__c ins = newScoredInspection(80, 100, 0);

    Assert.areEqual(
      '합격',
      judgementOf(ins),
      '득점률 0.8은 경계값으로 합격이어야 함 (BR-02). 부등호를 >= 에서 > 로 바꾸면 깨져야 한다'
    );
  }

  // S-02 득점률 0.79(합격선 바로 아래) → 시정 필요
  @IsTest
  static void rate79_correction() {
    Inspection__c ins = newScoredInspection(79, 100, 0);

    Assert.areEqual(
      '시정 필요',
      judgementOf(ins),
      '79점은 합격선 미만이므로 시정 필요'
    );
  }

  // S-03 득점률 0.6(시정선과 같음) → 시정 필요
  @IsTest
  static void rate60_correction() {
    Inspection__c ins = newScoredInspection(60, 100, 0);

    Assert.areEqual(
      '시정 필요',
      judgementOf(ins),
      '득점률 0.6은 경계값으로 시정 필요여야 함 (BR-02)'
    );
  }

  // S-04 득점률 0.59(시정선 바로 아래) → 불합격
  @IsTest
  static void rate59_fail() {
    Inspection__c ins = newScoredInspection(59, 100, 0);

    Assert.areEqual(
      '불합격',
      judgementOf(ins),
      '59점은 시정선 미만이므로 불합격'
    );
  }

  // S-05 100점 만점이어도 필수 항목 미흡 1건 → 불합격 (BR-03)
  @IsTest
  static void requiredDeficient_fail() {
    Inspection__c ins = newScoredInspection(100, 100, 1);

    Assert.areEqual(
      '불합격',
      judgementOf(ins),
      '필수 항목 미흡이 있으면 총점과 무관하게 불합격 (BR-03)'
    );
  }

  // S-06 배점 0 → 기존 판정을 건드리지 않음
  @IsTest
  static void maxScoreZero_keepsJudgement() {
    Inspection__c ins = newScoredInspection(0, 0, 0);
    ins.Judgement__c = '합격'; // DESC: 기존 판정이 있는 상태에서 시작 — '안 건드렸다'를 확인하기 위해

    InspectionService.applyJudgements(new List<Inspection__c>{ ins });

    Assert.areEqual(
      '합격',
      ins.Judgement__c,
      '배점이 0이면 기존 판정을 그대로 두어야 함. 가드를 지우면 0으로 나누기 예외가 난다'
    );
  }
  // S-07 배점 null → 예외 없이 건너뜀
  // TODO(Kai): S-07 보강 — 바로 위 S-06(maxScoreZero_keepsJudgement)처럼 판정을 미리 세팅하고
  //            그 값이 그대로인지 areEqual로 확인. 끝나면 메서드명을 maxScoreNull_keepsJudgement로 변경
  @IsTest
  static void maxScoreNull_keepsJudgement() {
    Inspection__c ins = newScoredInspection(0, null, 0);
    ins.Judgement__c = '합격';
    InspectionService.applyJudgements(new List<Inspection__c>{ ins });
    Assert.areEqual(
      '합격',
      ins.Judgement__c,
      '배점이 null이어도 예외 없이 건너뛰어야 함'
    );
  }
}
