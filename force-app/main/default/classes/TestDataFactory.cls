/* ======================================================================================
 * @description : 테스트용 데이터 생성기. 모든 테스트 클래스가 공유한다
 * @layer       : TestUtil
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.12   Kai        Created     최초 작성
 *  2026.10.12   Kai        Updated     리뷰 반영 — 컴파일 오류·반환·doInsert·개선 사항 수정
 *  2026.10.12   Kai        Updated     가맹점 매장코드·사업자번호, 점검번호 유니크 세팅 추가
 *  2026.10.12   Kai        Updated     점검번호를 호출 간에도 이어지게 변경 (한 테스트 내 중복 방지)
 *  2026.10.12   Kai        Updated     createCorrectiveActions 추가 (D6 기한 초과 배치 테스트용)
 * ======================================================================================
 *  @note        : @IsTest이므로 커버리지 분모에서 제외된다. doInsert = false면 insert 전 상태로
 *                 반환해 호출자가 필드를 더 손볼 수 있다 (벌크 테스트의 DML 1번 유지 목적)
 * ======================================================================================*/
@IsTest
public class TestDataFactory {
  public static final String RT_REGULAR = 'Regular';
  public static final String RT_REINSPECTION = 'Reinspection';
  public static final String RT_UNANNOUNCED = 'Unannounced';

  public static final String STATUS_SCHEDULED = '점검예정';
  public static final String STATUS_COMPLETED = '점검완료';

  // NOTE: InspectionNo__c는 Unique — 한 테스트에서 createInspections를 여러 번 불러도 겹치지 않게 호출 간 번호를 이어 간다
  private static Integer inspectionSeq = 0;

  // DESC: describe 기반이라 SOQL을 쓰지 않는다
  public static Id inspectionRecordTypeId(String developerName) {
    return Schema.SObjectType.Inspection__c
      .getRecordTypeInfosByDeveloperName()
      .get(developerName)
      .getRecordTypeId();
  }

  /**
   * @description : 가맹점을 생성한다. 이름·외부키를 인덱스로 유니크하게 만들어 Duplicate Rule을 피한다.
   * @author      : 이은석(Kai) | 2026.10.12
   * @param count     생성 건수
   * @param doInsert  true면 insert까지 수행 (DML 1번)
   * @return List<Account>
   **/
  public static List<Account> createFranchises(
    Integer count,
    Boolean doInsert
  ) {
    List<Account> franchises = new List<Account>();
    for (Integer i = 0; i < count; i++) {
      // NOTE: Account에 필수 커스텀 필드는 없다(describe 확인). StoreCode__c는 Unique External ID,
      //       BusinessRegNo__c는 Duplicate Rule(사업자번호 Exact 일치) 대상이라 인덱스로 유니크하게 채운다
      franchises.add(
        new Account(
          Name = 'TEST가맹점-' + String.valueOf(i).leftPad(4, '0'),
          StoreCode__c = 'TEST-STORE-' + String.valueOf(i).leftPad(4, '0'),
          BusinessRegNo__c = '999-99-' + String.valueOf(i).leftPad(5, '0')
        )
      );
    }
    if (doInsert) {
      insert franchises; // DML 1번 — 루프 밖
    }
    return franchises;
  }

  // ───────── 아래 3개는 Kai 작성 ─────────

  /**
   * @description : 점검을 생성한다.
   * @param franchises                   부모 가맹점
   * @param perFranchise                 가맹점당 건수
   * @param status                       Status__c
   * @param recordTypeDeveloperName      RT_REGULAR 등
   * @param inspectionDate               InspectionDate__c (최근 정기점검일 집계 대상)
   **/
  public static List<Inspection__c> createInspections(
    List<Account> franchises,
    Integer perFranchise,
    String status,
    String recordTypeDeveloperName,
    Date inspectionDate,
    Boolean doInsert
  ) {
    List<Inspection__c> inspections = new List<Inspection__c>();
    // PERF: describe는 루프 밖에서 1번만 호출한다
    Id recordTypeId = inspectionRecordTypeId(recordTypeDeveloperName);
    for (Account franchise : franchises) {
      for (Integer i = 0; i < perFranchise; i++) {
        inspections.add(
          new Inspection__c(
            Franchise__c = franchise.Id,
            Status__c = status,
            RecordTypeId = recordTypeId,
            InspectionDate__c = inspectionDate,
            InspectionNo__c = 'TEST-' +
              String.valueOf(inspectionSeq++).leftPad(4, '0')
          )
        );
      }
    }
    if (doInsert) {
      insert inspections;
    }
    return inspections;
  }

  /**
   * @description : 템플릿 항목을 생성한다. 앞의 requiredCount개를 위생 필수(IsRequired__c = true)로 만든다.
   * @note        : 필수 항목을 '앞쪽'에 두는 이유 — createResults의 scores 리스트와 인덱스가 맞아
   *                "필수는 만점, 비필수에서 감점" 조합을 호출자가 쉽게 만들 수 있다
   **/
  public static List<InspectionTemplateItem__c> createTemplateItems(
    Integer count,
    Integer requiredCount,
    Decimal maxScoreEach,
    Boolean doInsert
  ) {
    List<InspectionTemplateItem__c> templateItems = new List<InspectionTemplateItem__c>();
    for (Integer i = 0; i < count; i++) {
      Boolean isRequired = i < requiredCount;
      templateItems.add(
        new InspectionTemplateItem__c(
          Name = 'TEST템플릿항목-' + i,
          Category__c = isRequired ? '위생' : '서비스',
          IsRequired__c = isRequired,
          MaxScore__c = maxScoreEach,
          // WARN: 비우면 '활성 항목만 조회' 로직에서 테스트 데이터가 전부 걸러진다
          IsActive__c = true,
          SortOrder__c = i
        )
      );
    }
    if (doInsert) {
      insert templateItems;
    }
    return templateItems;
  }

  /**
   * @description : 결과 항목을 생성한다. items[i]의 점수가 scores[i]다.
   * @note        : BR-11 — 항목명·분류·배점·필수여부를 템플릿에서 '복사'한다. Lookup만 걸면
   *                Roll-Up ruMaxScore__c가 0이 되어 판정이 아예 실행되지 않는다
   **/
  public static List<InspectionResult__c> createResults(
    Inspection__c parent,
    List<InspectionTemplateItem__c> items,
    List<Decimal> scores,
    Boolean doInsert
  ) {
    if (scores == null || scores.size() != items.size()) {
      throw new IllegalArgumentException(
        'items와 scores의 크기가 같아야 합니다. items: ' +
          items.size() +
          ', scores: ' +
          (scores == null ? null : scores.size())
      );
    }

    List<InspectionResult__c> results = new List<InspectionResult__c>();
    for (Integer i = 0; i < items.size(); i++) {
      InspectionTemplateItem__c item = items[i];
      results.add(
        new InspectionResult__c(
          Inspection__c = parent.Id,
          TemplateItem__c = item.Id,
          Score__c = scores[i],
          // DESC: BR-11 스냅샷 — 템플릿 값을 복사한다
          ItemName__c = item.Name,
          Category__c = item.Category__c,
          MaxScore__c = item.MaxScore__c,
          IsRequired__c = item.IsRequired__c,
          // NOTE: 만점 미만이면 미흡으로 둔다. 다른 기준이 필요하면 doInsert = false로 받아 덮어쓴다
          IsDeficient__c = (scores[i] < item.MaxScore__c)
        )
      );
    }
    if (doInsert) {
      insert results;
    }
    return results;
  }

  /**
   * @description : 시정조치를 생성한다. 결과 항목(InspectionResult__c)이 Master-Detail 필수 부모다.
   * @note        : DueDate__c를 넘기면 '시정조치 기한 자동설정' Flow(BLANKVALUE)가 덮어쓰지 않는다.
   *                null을 넘기면 Flow가 분류에 따라 오늘 + 3일(위생) / 7일로 채운다
   * @param results      부모 결과 항목
   * @param perResult    결과 항목당 건수
   * @param status       Status__c ('요청' 등)
   * @param dueDate      DueDate__c
   * @param doInsert     true면 insert까지 수행 (DML 1번)
   **/
  public static List<CorrectiveAction__c> createCorrectiveActions(
    List<InspectionResult__c> results,
    Integer perResult,
    String status,
    Date dueDate,
    Boolean doInsert
  ) {
    List<CorrectiveAction__c> correctiveActions = new List<CorrectiveAction__c>();
    for (InspectionResult__c result : results) {
      for (Integer i = 0; i < perResult; i++) {
        correctiveActions.add(
          new CorrectiveAction__c(
            InspectionResult__c = result.Id,
            Status__c = status,
            DueDate__c = dueDate
          )
        );
      }
    }
    if (doInsert) {
      insert correctiveActions;
    }
    return correctiveActions;
  }
}
