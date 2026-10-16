/* ======================================================================================
 * @description : 출고 제한 수신 API(IF-001)의 신규 접수 · 재전송 멱등성 · 요청 검증을 검증하는 테스트 클래스
 * @testTarget  : SupplyRestrictionRestResource, SupplyRestrictionService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.16   Kai        Created     최초 작성 — 201 · 같은 키 200 · 400(필수 누락 · 날짜 역전 · 상관 ID 길이 등)
 * ======================================================================================
 *  @see         : SupplyRestrictionService.cls
 *  @note        : 실제 호출자와 같은 연동 사용자(API 전용 프로필 + Salesforce API Integration PSL + 「출고 제한 수신」)로
 *                 System.runAs 해서 RestContext 요청을 보낸다 — 권한 집합이 USER_MODE 조회 · 저장에 충분한지도 함께 검증된다.
 *                 준비 데이터 insert와 결과 확인 조회는 테스트 대상이 아니라 시스템 모드로 한다.
 *                 TestDataFactory는 kai-dev 패키지(force-app) 소속이라 물류 org에 없어 이 클래스의 도우미로 만든다.
 *                 요청 1건 = 레코드 1건인 API라 200건 벌크 케이스는 해당 없음
 * ======================================================================================*/
@IsTest
private class SupplyRestrictionRestResourceTest {
  // NOTE: 송신 측 페널티 Id 형식(18자)의 임의 값
  private static final String CORRELATION_ID = 'a0BdL00000AbCdEFGH';
  private static final String STORE_CODE = 'GN-0001';
  private static final Date START_DATE = Date.newInstance(2026, 10, 20);
  private static final Date END_DATE = Date.newInstance(2026, 10, 27);

  private static final String INTEGRATION_USER_LAST_NAME = '물류연동테스트';
  private static final String INTEGRATION_PROFILE = 'Minimum Access - API Only Integrations';
  private static final String INTEGRATION_PSL = 'SalesforceAPIIntegrationPsl';
  private static final String API_PERMISSION_SET = 'SupplyRestrictionApiAccess';

  // DESC: 호출자 연동 사용자를 만든다. 사용자 · 라이선스 · 권한 집합 할당은 설정(setup) 개체라 업무 데이터와
  //       같은 트랜잭션에서 만들면 MIXED_DML_OPERATION이 난다 → @TestSetup에 모으고 업무 데이터는 각 테스트에서 만든다
  @TestSetup
  static void createIntegrationUser() {
    User integrationUser = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = :INTEGRATION_PROFILE]
      .Id,
      LastName = INTEGRATION_USER_LAST_NAME,
      Alias = 'tlogi',
      Email = 'test.logistics@example.com',
      // NOTE: 사용자명은 org 전체(다른 org 포함)에서 유일해야 해 난수를 붙인다
      Username = 'test.logistics.' +
        String.valueOf(Crypto.getRandomInteger()).replace('-', '') +
        '@example.com',
      TimeZoneSidKey = 'Asia/Seoul',
      LocaleSidKey = 'ko_KR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'ko'
    );
    insert integrationUser;
    insert new PermissionSetLicenseAssign(
      AssigneeId = integrationUser.Id,
      PermissionSetLicenseId = [
        SELECT Id
        FROM PermissionSetLicense
        WHERE DeveloperName = :INTEGRATION_PSL
      ]
      .Id
    );
    insert new PermissionSetAssignment(
      AssigneeId = integrationUser.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = :API_PERMISSION_SET
      ]
      .Id
    );
  }

  // 증명: 새 상관 ID는 201 + 접수번호이고, 레코드는 본문 값 · 접수 · 미전송으로 1건 생긴다
  @IsTest
  static void post_newCorrelationId_returns201AndCreatesRecord() {
    RestResponse res;
    Test.startTest();
    System.runAs(integrationUser()) {
      res = post(CORRELATION_ID, validPayload());
    }
    Test.stopTest();

    Assert.areEqual(
      201,
      res.statusCode,
      '처음 받은 상관 ID는 신규 접수(201)여야 한다. 응답: ' +
      res.responseBody.toString()
    );
    SupplyRestriction__c saved = getOnlyRestriction();
    Map<String, Object> body = readBody(res);
    Assert.areEqual(
      saved.Name,
      body.get('requestNo'),
      '응답 접수번호는 저장된 레코드의 자동번호여야 한다'
    );
    Assert.isTrue(
      saved.Name.startsWith('SR-'),
      '접수번호 형식은 SR-{000000}이어야 한다. 실제: ' + saved.Name
    );
    Assert.areEqual(
      'RECEIVED',
      body.get('status'),
      '신규 접수의 응답 상태는 RECEIVED여야 한다'
    );
    Assert.areEqual(
      CORRELATION_ID,
      saved.CorrelationId__c,
      '상관 ID가 저장돼야 한다'
    );
    Assert.areEqual(STORE_CODE, saved.StoreCode__c, '매장코드가 저장돼야 한다');
    Assert.areEqual(
      START_DATE,
      saved.StartDate__c,
      '제한 시작일이 저장돼야 한다'
    );
    Assert.areEqual(END_DATE, saved.EndDate__c, '제한 종료일이 저장돼야 한다');
    Assert.isNotNull(saved.Reason__c, '사유가 저장돼야 한다');
    Assert.areEqual(
      SupplyRestrictionService.STATUS_RECEIVED,
      saved.Status__c,
      '처리 상태는 접수로 시작해야 한다'
    );
    Assert.areEqual(
      SupplyRestrictionService.CALLBACK_NOT_SENT,
      saved.CallbackStatus__c,
      '회신 상태는 미전송으로 시작해야 한다'
    );
  }

  // 증명: 같은 상관 ID를 다시 보내면 200 + 같은 접수번호이고, 레코드는 1건이며 두 번째 본문으로 바뀌지 않는다
  @IsTest
  static void post_sameCorrelationIdTwice_returns200WithSameRequestNo() {
    Map<String, Object> resent = validPayload();
    resent.put('endDate', Date.newInstance(2026, 12, 31));
    RestResponse first;
    RestResponse second;

    Test.startTest();
    System.runAs(integrationUser()) {
      first = post(CORRELATION_ID, validPayload());
      second = post(CORRELATION_ID, resent);
    }
    Test.stopTest();

    Assert.areEqual(201, first.statusCode, '첫 전송은 신규 접수(201)여야 한다');
    Assert.areEqual(
      200,
      second.statusCode,
      '같은 상관 ID 재전송은 200이어야 한다(멱등성)'
    );
    Assert.areEqual(
      readBody(first).get('requestNo'),
      readBody(second).get('requestNo'),
      '재전송에는 기존 접수번호를 돌려줘야 송신 측이 같은 건으로 안다'
    );
    SupplyRestriction__c saved = getOnlyRestriction();
    Assert.areEqual(
      END_DATE,
      saved.EndDate__c,
      '재전송 본문으로 기존 접수를 바꾸면 안 된다'
    );
  }

  // 증명: 이미 처리된 건을 다시 받으면 현재 상태 코드(APPLIED)를 돌려준다
  @IsTest
  static void post_resentAfterApplied_returnsCurrentStatus() {
    SupplyRestriction__c applied = insertRestriction(
      SupplyRestrictionService.STATUS_APPLIED
    );
    RestResponse res;

    Test.startTest();
    System.runAs(integrationUser()) {
      res = post(CORRELATION_ID, validPayload());
    }
    Test.stopTest();

    Assert.areEqual(200, res.statusCode, '이미 있는 상관 ID는 200이어야 한다');
    Map<String, Object> body = readBody(res);
    Assert.areEqual(
      applied.Name,
      body.get('requestNo'),
      '기존 접수번호를 돌려줘야 한다'
    );
    Assert.areEqual(
      'APPLIED',
      body.get('status'),
      '재전송 응답은 현재 처리 상태를 알려 줘야 송신 측이 상태를 되돌리지 않는다'
    );
  }

  // 증명: 조회 뒤 다른 요청이 먼저 저장한 경우(동시 재전송) Unique 충돌을 200 + 기존 접수번호로 바꾼다
  @IsTest
  static void insertOrFindExisting_duplicateValue_returns200() {
    SupplyRestriction__c first = insertRestriction(
      SupplyRestrictionService.STATUS_RECEIVED
    );
    SupplyRestriction__c racing = newRestriction(
      SupplyRestrictionService.STATUS_RECEIVED
    );
    SupplyRestrictionService.ReceiveResult result;

    Test.startTest();
    System.runAs(integrationUser()) {
      result = SupplyRestrictionService.insertOrFindExisting(racing);
    }
    Test.stopTest();

    Assert.areEqual(
      200,
      result.statusCode,
      'Unique 충돌(DUPLICATE_VALUE)은 오류가 아니라 재전송(200)으로 처리해야 한다'
    );
    Assert.areEqual(
      first.Name,
      result.requestNo,
      '먼저 저장된 건의 접수번호를 돌려줘야 한다'
    );
    getOnlyRestriction();
  }

  // 증명: 필수 값(매장코드 · 시작일 · 종료일)이 없으면 400이고, 빠진 키를 모두 알려 주며 저장하지 않는다
  @IsTest
  static void post_missingRequiredFields_returns400() {
    RestResponse res;
    Test.startTest();
    System.runAs(integrationUser()) {
      res = post(
        CORRELATION_ID,
        new Map<String, Object>{ 'reason' => '사유만 있음' }
      );
    }
    Test.stopTest();

    Assert.areEqual(400, res.statusCode, '필수 값이 빠지면 400이어야 한다');
    String error = readError(res);
    for (String key : new List<String>{ 'storeCode', 'startDate', 'endDate' }) {
      Assert.isTrue(
        error.contains(key),
        '오류 메시지에 빠진 키 ' + key + '가 있어야 한다. 실제: ' + error
      );
    }
    assertNothingSaved();
  }

  // 증명: 시작일이 종료일보다 늦으면 400
  @IsTest
  static void post_startDateAfterEndDate_returns400() {
    Map<String, Object> payload = validPayload();
    payload.put('startDate', END_DATE.addDays(1));
    RestResponse res;

    Test.startTest();
    System.runAs(integrationUser()) {
      res = post(CORRELATION_ID, payload);
    }
    Test.stopTest();

    Assert.areEqual(400, res.statusCode, '기간이 뒤집히면 400이어야 한다');
    Assert.isTrue(
      readError(res).contains('startDate'),
      '오류 메시지에 날짜 역전이 드러나야 한다. 실제: ' + readError(res)
    );
    assertNothingSaved();
  }

  // 증명: 상관 ID 헤더가 없거나 18자가 아니면 400 — 멱등성 키가 없으면 재전송을 알아볼 수 없다
  @IsTest
  static void post_invalidCorrelationId_returns400() {
    List<String> invalidIds = new List<String>{
      null,
      CORRELATION_ID.left(17),
      CORRELATION_ID + 'X'
    };
    List<RestResponse> responses = new List<RestResponse>();

    Test.startTest();
    System.runAs(integrationUser()) {
      for (String invalidId : invalidIds) {
        responses.add(post(invalidId, validPayload()));
      }
    }
    Test.stopTest();

    for (Integer i = 0; i < responses.size(); i++) {
      Assert.areEqual(
        400,
        responses[i].statusCode,
        '상관 ID ' + invalidIds[i] + '는 400이어야 한다'
      );
      Assert.isTrue(
        readError(responses[i])
          .contains(SupplyRestrictionService.HEADER_CORRELATION_ID),
        '오류 메시지에 헤더 이름이 있어야 한다. 실제: ' +
        readError(responses[i])
      );
    }
    assertNothingSaved();
  }

  // 증명: yyyy-MM-dd가 아니거나 없는 날짜(2월 30일)는 400 — 다음 달로 넘겨 저장하지 않는다
  @IsTest
  static void post_invalidDate_returns400() {
    Map<String, Object> slashFormat = validPayload();
    slashFormat.put('startDate', '2026/10/20');
    Map<String, Object> notExisting = validPayload();
    notExisting.put('endDate', '2027-02-30');
    RestResponse slashRes;
    RestResponse notExistingRes;

    Test.startTest();
    System.runAs(integrationUser()) {
      slashRes = post(CORRELATION_ID, slashFormat);
      notExistingRes = post(CORRELATION_ID, notExisting);
    }
    Test.stopTest();

    Assert.areEqual(
      400,
      slashRes.statusCode,
      'yyyy-MM-dd가 아니면 400이어야 한다'
    );
    Assert.isTrue(
      readError(slashRes).contains('startDate'),
      '형식이 틀린 키가 드러나야 한다. 실제: ' + readError(slashRes)
    );
    Assert.areEqual(
      400,
      notExistingRes.statusCode,
      '없는 날짜는 400이어야 한다'
    );
    Assert.isTrue(
      readError(notExistingRes).contains('endDate'),
      '없는 날짜인 키가 드러나야 한다. 실제: ' + readError(notExistingRes)
    );
    assertNothingSaved();
  }

  // 증명: 본문이 JSON 객체가 아니면(배열 · 깨진 JSON) 400
  @IsTest
  static void post_bodyNotJsonObject_returns400() {
    RestResponse arrayRes;
    RestResponse brokenRes;
    Test.startTest();
    System.runAs(integrationUser()) {
      arrayRes = postRaw(CORRELATION_ID, '[1, 2]');
      brokenRes = postRaw(CORRELATION_ID, '{"storeCode": ');
    }
    Test.stopTest();

    Assert.areEqual(
      400,
      arrayRes.statusCode,
      'JSON 배열 본문은 400이어야 한다'
    );
    Assert.areEqual(
      400,
      brokenRes.statusCode,
      '깨진 JSON 본문은 400이어야 한다'
    );
    assertNothingSaved();
  }

  // ---------------------------------------------------------------- 도우미

  private static User integrationUser() {
    return [
      SELECT Id
      FROM User
      WHERE
        LastName = :INTEGRATION_USER_LAST_NAME
        AND Profile.Name = :INTEGRATION_PROFILE
      LIMIT 1
    ];
  }

  // DESC: 송신 측(LogisticsNotifyService)처럼 Date를 JSON.serialize해 yyyy-MM-dd 문자열로 보낸다
  private static Map<String, Object> validPayload() {
    return new Map<String, Object>{
      'storeCode' => STORE_CODE,
      'startDate' => START_DATE,
      'endDate' => END_DATE,
      'reason' => '같은 항목 3회 연속 지적 (BR-08)'
    };
  }

  private static RestResponse post(
    String correlationId,
    Map<String, Object> payload
  ) {
    return postRaw(correlationId, JSON.serialize(payload));
  }

  private static RestResponse postRaw(String correlationId, String body) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/v1/supply-restrictions';
    req.httpMethod = 'POST';
    if (correlationId != null) {
      req.addHeader(
        SupplyRestrictionService.HEADER_CORRELATION_ID,
        correlationId
      );
    }
    req.requestBody = Blob.valueOf(body);
    RestContext.request = req;
    RestContext.response = new RestResponse();
    SupplyRestrictionRestResource.receive();
    return RestContext.response;
  }

  private static Map<String, Object> readBody(RestResponse res) {
    return (Map<String, Object>) JSON.deserializeUntyped(
      res.responseBody.toString()
    );
  }

  private static String readError(RestResponse res) {
    return (String) readBody(res).get('error');
  }

  private static SupplyRestriction__c newRestriction(String status) {
    return new SupplyRestriction__c(
      CorrelationId__c = CORRELATION_ID,
      StoreCode__c = STORE_CODE,
      StartDate__c = START_DATE,
      EndDate__c = END_DATE,
      Status__c = status,
      CallbackStatus__c = SupplyRestrictionService.CALLBACK_NOT_SENT
    );
  }

  // NOTE: 준비 데이터는 테스트 대상이 아니다 — 실행 사용자(관리자)의 FLS와 무관하게 as system으로 만든다
  private static SupplyRestriction__c insertRestriction(String status) {
    SupplyRestriction__c restriction = newRestriction(status);
    insert as system restriction;
    return [
      SELECT Id, Name
      FROM SupplyRestriction__c
      WHERE Id = :restriction.Id
      WITH SYSTEM_MODE
    ];
  }

  // NOTE: 결과 확인 조회도 테스트 대상이 아니다 — DB에 실제로 남은 값을 보려고 WITH SYSTEM_MODE
  private static SupplyRestriction__c getOnlyRestriction() {
    List<SupplyRestriction__c> restrictions = [
      SELECT
        Name,
        CorrelationId__c,
        StoreCode__c,
        StartDate__c,
        EndDate__c,
        Reason__c,
        Status__c,
        CallbackStatus__c
      FROM SupplyRestriction__c
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      1,
      restrictions.size(),
      '같은 상관 ID의 출고 제한은 1건이어야 한다'
    );
    return restrictions[0];
  }

  private static void assertNothingSaved() {
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM SupplyRestriction__c WITH SYSTEM_MODE],
      '검증에 실패한 요청은 저장하면 안 된다'
    );
  }
}
