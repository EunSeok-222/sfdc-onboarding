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
 *  2026.10.14   Kai        Updated     createSvUser 이동 (InspectionTriggerHandlerTest → 공유, D8 runAs 테스트용)
 *  2026.10.14   Kai        Updated     createSupplyRestrictionPenalties 추가 (D8 물류 통보 콜아웃 테스트용)
 *  2026.10.16   Kai        Updated     createRegionManagerUser 추가 (D10 승인 → 물류 통보 runAs 테스트용)
 *  2026.10.17   Kai        Updated     createLogisticsNotifyLogs 추가 (D10 인터페이스 로그 Outbox 테스트용)
 *  2026.10.17   Kai        Updated     createIntegrationUser 추가 (D11 연동 사용자 권한 아웃박스 처리 테스트용)
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

  /** 권한 매트릭스 V1.2의 SV 프로필 이름 */
  public static final String PROFILE_SV = '가맹점점검 SV';
  /** 권한 매트릭스 V1.2의 권역팀장 프로필 이름 (페널티 승인자) */
  public static final String PROFILE_REGION_MANAGER = '가맹점점검 권역팀장';
  /** 연동 사용자 프로필 (Salesforce Integration 라이선스) */
  public static final String PROFILE_INTEGRATION = 'Minimum Access - API Only Integrations';

  // NOTE: InspectionNo__c는 Unique — 한 테스트에서 createInspections를 여러 번 불러도 겹치지 않게 호출 간 번호를 이어 간다
  private static Integer inspectionSeq = 0;

  // PERF: 사용자를 여러 명 만들어도 프로필 SOQL은 트랜잭션당 1번만 실행한다
  private static Id svProfileId;
  private static Id regionManagerProfileId;
  private static Id integrationProfileId;

  /**
   * @description : 「가맹점점검 SV」 프로필 사용자를 생성한다. 테스트 안에서만 존재해 라이선스를 쓰지 않는다.
   * @author      : 이은석(Kai) | 2026.10.14
   * @note        : 역할(UserRoleId)을 비워 둔다 — 역할이 없는 사용자는 업무 데이터와 같은 트랜잭션에서
   *                insert해도 Mixed DML 오류가 나지 않는다. 사용자명은 org 전체에서 유일해야 하므로 난수를 붙인다
   * @param lastName  성 (테스트에서 사용자를 다시 찾을 때 키로 쓴다)
   * @param doInsert  true면 insert까지 수행 (DML 1번)
   * @return User
   **/
  public static User createSvUser(String lastName, Boolean doInsert) {
    if (svProfileId == null) {
      svProfileId = [SELECT Id FROM Profile WHERE Name = :PROFILE_SV].Id;
    }
    return newUser(svProfileId, 'tsv', 'test.sv', lastName, doInsert);
  }

  /**
   * @description : 「가맹점점검 권역팀장」 프로필 사용자를 생성한다. 페널티 승인자(SV의 Manager)로 쓴다.
   * @author      : 이은석(Kai) | 2026.10.16
   * @note        : createSvUser와 같이 역할을 비워 Mixed DML을 피한다
   * @param lastName  성 (테스트에서 사용자를 다시 찾을 때 키로 쓴다)
   * @param doInsert  true면 insert까지 수행 (DML 1번)
   * @return User
   **/
  public static User createRegionManagerUser(
    String lastName,
    Boolean doInsert
  ) {
    if (regionManagerProfileId == null) {
      regionManagerProfileId = [
        SELECT Id
        FROM Profile
        WHERE Name = :PROFILE_REGION_MANAGER
      ]
      .Id;
    }
    return newUser(
      regionManagerProfileId,
      'trm',
      'test.rm',
      lastName,
      doInsert
    );
  }

  /**
   * @description : 연동 사용자와 같은 「Minimum Access - API Only Integrations」 프로필 사용자를 생성한다.
   *                역할 · 공유 경로가 없는 실행 사용자로 아웃박스 처리를 검증할 때 쓴다.
   * @author      : 이은석(Kai) | 2026.10.17
   * @note        : 역할을 비워 Mixed DML을 피한다. 권한 집합 · PSL은 할당하지 않는다(콜아웃은 테스트에서 Mock)
   * @param lastName  성 (테스트에서 사용자를 다시 찾을 때 키로 쓴다)
   * @param doInsert  true면 insert까지 수행 (DML 1번)
   * @return User
   **/
  public static User createIntegrationUser(String lastName, Boolean doInsert) {
    if (integrationProfileId == null) {
      integrationProfileId = [
        SELECT Id
        FROM Profile
        WHERE Name = :PROFILE_INTEGRATION
      ]
      .Id;
    }
    return newUser(
      integrationProfileId,
      'tint',
      'test.int',
      lastName,
      doInsert
    );
  }

  // NOTE: 사용자명은 org 전체에서 유일해야 하므로 난수를 붙인다
  private static User newUser(
    Id profileId,
    String alias,
    String usernamePrefix,
    String lastName,
    Boolean doInsert
  ) {
    String uniqueKey = String.valueOf(Crypto.getRandomInteger())
      .replace('-', '');
    User newUser = new User(
      ProfileId = profileId,
      LastName = lastName,
      Alias = alias,
      Email = usernamePrefix + '@example.com',
      Username = usernamePrefix + '.' + uniqueKey + '@example.com',
      TimeZoneSidKey = 'Asia/Seoul',
      LocaleSidKey = 'ko_KR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'ko'
    );
    if (doInsert) {
      insert newUser;
    }
    return newUser;
  }

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

  /**
   * @description : 가맹점마다 승인된 공급 제한 페널티(BR-08)를 1건씩 만든다. 기간은 내일부터 1주.
   * @author      : 이은석(Kai) | 2026.10.14
   * @note        : 물류 통보 대상 조건(유형 공급 제한 · 승인 · 기간 · 매장코드)을 모두 채운다.
   *                매장코드는 createFranchises가 채우므로 그 가맹점을 넘긴다
   * @param franchises 부모 가맹점 (StoreCode__c가 있어야 통보 대상)
   * @param doInsert   true면 insert까지 수행 (DML 1번)
   * @return List<Penalty__c>
   **/
  public static List<Penalty__c> createSupplyRestrictionPenalties(
    List<Account> franchises,
    Boolean doInsert
  ) {
    List<Penalty__c> penalties = new List<Penalty__c>();
    for (Account franchise : franchises) {
      penalties.add(
        new Penalty__c(
          Franchise__c = franchise.Id,
          PenaltyType__c = LogisticsNotifyService.PENALTY_TYPE_SUPPLY_RESTRICTION,
          Status__c = LogisticsNotifyService.PENALTY_STATUS_APPROVED,
          StartDate__c = Date.today().addDays(1),
          EndDate__c = Date.today().addDays(7),
          Reason__c = '같은 항목 3회 연속 지적 (BR-08)'
        )
      );
    }
    if (doInsert) {
      insert penalties;
    }
    return penalties;
  }

  /**
   * @description : 페널티마다 물류 통보(IF-001) 인터페이스 로그를 1건씩 만든다. 다음 시도 시각은 비워 바로 처리 대상이 된다.
   * @author      : 이은석(Kai) | 2026.10.17
   * @note        : 로그는 시스템 기록이라 실행 사용자 FLS와 무관하게 as system으로 넣는다(운영 코드와 같은 방식)
   * @param penalties    대상 페널티 (저장된 것)
   * @param status       로그 상태 (LogisticsNotifyService.LOG_STATUS_*)
   * @param attemptCount 지금까지 보낸 횟수
   * @param doInsert     true면 insert까지 수행 (DML 1번)
   * @return List<IntegrationLog__c>
   **/
  public static List<IntegrationLog__c> createLogisticsNotifyLogs(
    List<Penalty__c> penalties,
    String status,
    Integer attemptCount,
    Boolean doInsert
  ) {
    List<IntegrationLog__c> logs = new List<IntegrationLog__c>();
    for (Penalty__c penalty : penalties) {
      logs.add(
        new IntegrationLog__c(
          Penalty__c = penalty.Id,
          InterfaceId__c = LogisticsNotifyService.INTERFACE_ID,
          Direction__c = LogisticsNotifyService.DIRECTION_OUTBOUND,
          Status__c = status,
          CorrelationId__c = penalty.Id,
          AttemptCount__c = attemptCount
        )
      );
    }
    if (doInsert) {
      insert as system logs;
    }
    return logs;
  }
}
