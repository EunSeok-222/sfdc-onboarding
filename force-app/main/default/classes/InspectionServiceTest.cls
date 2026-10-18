/* ======================================================================================
 * @description : InspectionService 단위 테스트 — 판정 계산(BR-02 · BR-03) 경계값 중심
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.12   Kai        Created     최초 작성 — applyJudgements 경계값
 *  2026.10.12   Kai        Updated     메서드명 축약 (Apex 식별자는 ASCII만 허용 — 설명은 주석으로)
 *  2026.10.14   Kai        Updated     판정 필드 편집 FLS 테스트 추가 (SV runAs · stripInaccessible · USER_MODE)
 *  2026.10.18   Kai        Updated     judgeInspections · countInspectionsByFranchise(D4 집계 · 일괄 처리) 테스트 추가(Step 8)
 * ======================================================================================
 *  @see         : InspectionService.cls, docs/d6-test-scenarios.md
 *  @note        : applyJudgements는 SOQL · DML이 없어 레코드를 insert하지 않고 검증한다.
 *                 Roll-Up은 생성자로 대입 불가. JSON 역직렬화로 값을 주입한다
 *                 판정 FLS 테스트(judgementFls_*)만 SV 권한을 재현하려고 실제 레코드를 insert한다
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

  // ---------------------------------------------------------------- 판정 필드 편집 FLS (권한 축소 사용자)
  // NOTE: 권한 매트릭스 V1.2 — 판정(Judgement__c)은 관리자만 편집, SV · 권역팀장 · 조회전용은 읽기 전용.
  //       InspectionService가 판정을 쓰는 update는 시스템 모드여야 SV의 점검완료 저장이 실패하지 않는다. 그 근거를 테스트로 남긴다
  // WARN: 점검완료 점검은 상태가 점검완료로 바뀌거나 Roll-Up 점수가 바뀌는 update에서 트리거
  //       (InspectionTriggerHandler.applyJudgementsOnCompletion)가 판정을 다시 계산해 덮어쓴다.
  //       판정 저장 자체만 보려고 대상 점검은 점검예정으로 만든다 — 재계산이 끼어들면 "저장됐다/막혔다"를 잘못 읽는다

  private static final String JUDGEMENT_PASS = '합격';

  // 증명: 플랫폼이 SV에게 판정을 '수정 불가 필드'로 본다 (예외 없이 결정적으로 확인)
  @IsTest
  static void judgementFls_svStripInaccessible_removesJudgement() {
    User sv = TestDataFactory.createSvUser('판정FLS테스트SV', true);
    Id inspectionId = insertScheduledInspection(sv.Id);

    SObjectAccessDecision decision;
    Test.startTest();
    System.runAs(sv) {
      Inspection__c target = [
        SELECT Id, Judgement__c
        FROM Inspection__c
        WHERE Id = :inspectionId
      ];
      target.Judgement__c = JUDGEMENT_PASS;
      decision = Security.stripInaccessible(
        AccessType.UPDATABLE,
        new List<Inspection__c>{ target }
      );
    }
    Test.stopTest();

    Map<String, Set<String>> removedFieldsByObject = decision.getRemovedFields();
    Assert.isTrue(
      removedFieldsByObject.containsKey('Inspection__c') &&
      removedFieldsByObject.get('Inspection__c').contains('Judgement__c'),
      'SV 기준 수정 불가 필드에 판정이 있어야 한다. 실제: ' +
      removedFieldsByObject
    );
  }

  // 증명: SV 권한(USER_MODE)으로 판정을 저장하면 막히고, DB 값도 그대로다
  @IsTest
  static void judgementFls_svUserModeUpdate_isBlocked() {
    User sv = TestDataFactory.createSvUser('판정FLS테스트SV', true);
    Id inspectionId = insertScheduledInspection(sv.Id);

    // NOTE: Assert.fail을 try 안에 두면 catch(Exception)가 그 실패까지 삼켜 테스트가 거짓 통과한다 → 결과를 변수로 받고 밖에서 검증
    Boolean saved = false;
    DmlException caught;
    Test.startTest();
    System.runAs(sv) {
      Inspection__c target = new Inspection__c(
        Id = inspectionId,
        Judgement__c = JUDGEMENT_PASS
      );
      try {
        Database.update(target, AccessLevel.USER_MODE);
        saved = true;
      } catch (DmlException e) {
        // NOTE: 2026.10.14 디버그 로그로 확인한 실제 예외 — System.DmlException,
        //       "Operation failed due to fields being inaccessible on Sobject Inspection__c ..." · getDmlFieldNames(0) = (Judgement__c)
        caught = e;
      }
    }
    Test.stopTest();

    Assert.isFalse(saved, 'SV 권한으로 판정이 저장되면 안 된다');
    Assert.isNotNull(caught, '저장이 막혔다면 DmlException이 있어야 한다');
    Assert.isTrue(
      caught.getMessage().contains('fields being inaccessible'),
      '필드 권한 때문에 막혀야 한다(다른 이유가 아니라). 실제: ' +
      caught.getMessage()
    );
    Assert.isTrue(
      caught.getDmlFieldNames(0).contains('Judgement__c'),
      '막힌 필드가 판정이어야 한다. 실제: ' + caught.getDmlFieldNames(0)
    );
    Assert.isNull(
      [SELECT Judgement__c FROM Inspection__c WHERE Id = :inspectionId]
      .Judgement__c,
      '막힌 저장은 DB 판정 값을 바꾸면 안 된다'
    );
  }

  // 증명(대조군): 같은 점검 · 같은 저장문을 판정 편집 권한이 있는 관리자가 실행하면 성공한다
  //               → 2번 테스트를 막은 것은 코드가 아니라 SV의 필드 권한이다
  @IsTest
  static void judgementFls_adminSameUpdate_succeeds() {
    User sv = TestDataFactory.createSvUser('판정FLS테스트SV', true);
    Id inspectionId = insertScheduledInspection(sv.Id);

    Test.startTest();
    Database.SaveResult result = Database.update(
      new Inspection__c(Id = inspectionId, Judgement__c = JUDGEMENT_PASS),
      false,
      AccessLevel.USER_MODE
    );
    Test.stopTest();

    Assert.isTrue(
      result.isSuccess(),
      '관리자는 같은 저장이 성공해야 한다. 실제 오류: ' + result.getErrors()
    );
    Assert.areEqual(
      JUDGEMENT_PASS,
      [SELECT Judgement__c FROM Inspection__c WHERE Id = :inspectionId]
      .Judgement__c,
      '관리자 저장 후 판정이 반영되어야 한다'
    );
  }

  // 증명: judgeInspections(D4 일괄 처리) — 결과 항목이 있는 점검만 판정을 저장하고, 배점 합계 0인 점검은 건너뛴다.
  //       빈 집합 · null이면 SOQL · DML 없이 끝난다
  @IsTest
  static void judgeInspections_savesOnlyScoredInspections() {
    List<Inspection__c> inspections = TestDataFactory.createInspections(
      TestDataFactory.createFranchises(2, true),
      1,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    );
    Inspection__c scored = inspections[0];
    Inspection__c empty = inspections[1];
    // NOTE: 34 / 40 = 85% · 필수 미흡 없음 → 합격. 점검예정이라 트리거는 판정을 다시 계산하지 않는다
    insert TestDataFactory.createResults(
      scored,
      TestDataFactory.createTemplateItems(4, 1, 10, true),
      new List<Decimal>{ 9, 9, 8, 8 },
      false
    );

    Test.startTest();
    Integer dmlBefore = Limits.getDmlStatements();
    InspectionService.judgeInspections(new Set<Id>());
    InspectionService.judgeInspections(null);
    Integer dmlForEmpty = Limits.getDmlStatements() - dmlBefore;
    InspectionService.judgeInspections(new Set<Id>{ scored.Id, empty.Id });
    Test.stopTest();

    Map<Id, Inspection__c> savedById = new Map<Id, Inspection__c>(
      [SELECT Judgement__c FROM Inspection__c WHERE Id IN :inspections]
    );
    Assert.areEqual(0, dmlForEmpty, '빈 집합 · null이면 저장하지 않는다');
    Assert.areEqual(
      JUDGEMENT_PASS,
      savedById.get(scored.Id).Judgement__c,
      '결과 항목이 있는 점검은 판정을 저장한다'
    );
    Assert.isNull(
      savedById.get(empty.Id).Judgement__c,
      '배점 합계 0(결과 항목 없음)은 판정하지 않는다'
    );
  }

  // 증명: countInspectionsByFranchise(D4 집계) — 가맹점별 점검 건수, 점검이 없는 가맹점은 0
  @IsTest
  static void countInspectionsByFranchise_includesZero() {
    List<Account> franchises = TestDataFactory.createFranchises(2, true);
    TestDataFactory.createInspections(
      new List<Account>{ franchises[0] },
      3,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      true
    );

    Test.startTest();
    Map<Id, Integer> countsByFranchiseId = InspectionService.countInspectionsByFranchise(
      new Map<Id, Account>(franchises).keySet()
    );
    Test.stopTest();

    Assert.areEqual(3, countsByFranchiseId.get(franchises[0].Id), '점검 3건');
    Assert.areEqual(
      0,
      countsByFranchiseId.get(franchises[1].Id),
      '점검이 없는 가맹점도 0으로 포함'
    );
  }

  /** SV 소유 점검예정 점검 1건 (판정 재계산이 일어나지 않는 상태) */
  private static Id insertScheduledInspection(Id ownerId) {
    Inspection__c ins = TestDataFactory.createInspections(
      TestDataFactory.createFranchises(1, true),
      1,
      TestDataFactory.STATUS_SCHEDULED,
      TestDataFactory.RT_REGULAR,
      Date.today(),
      false
    )[0];
    ins.OwnerId = ownerId;
    insert ins;
    return ins.Id;
  }
}
