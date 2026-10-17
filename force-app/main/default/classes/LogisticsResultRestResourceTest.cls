/* ======================================================================================
 * @description : 반영 결과 회신 수신 API(IF-004)의 기록 · 재수신 멱등성 · 요청 검증 · 상태 불일치를 검증하는 테스트 클래스
 * @testTarget  : LogisticsResultRestResource, LogisticsResultService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 200 RECORDED · 200 UNCHANGED · 400 · 404 · 409 · 500(롤백), 소유자 규칙 3경우(Step 7-A)
 * ======================================================================================
 *  @see         : LogisticsResultService.cls, 인터페이스 정의서 V1.1 IF-004
 *  @note        : 실제 호출자와 같은 프로필(Minimum Access - API Only Integrations, 역할 없음)의 연동 사용자로 System.runAs 해
 *                 RestContext 요청을 보낸다. 페널티는 다른 사람(SV) 소유라 연동 사용자에게는 공유 경로가 없다.
 *                 준비 데이터 insert와 결과 확인 조회는 테스트 대상이 아니라 테스트 실행 사용자(관리자)로 한다.
 *                 요청 1건 = 로그 1건인 API라 200건 벌크 케이스는 해당 없음
 * ======================================================================================*/
@IsTest
private class LogisticsResultRestResourceTest {
  private static final String REQUEST_NO = 'SR-000123';
  private static final String PROCESSED_AT = '2026-10-18T01:00:00Z';
  private static final String REJECT_MESSAGE = '매장 폐점 예정으로 반영 불가';

  private static final String INTEGRATION_LAST_NAME = '결과수신테스트연동';
  private static final String READER_LAST_NAME = '결과수신테스트SV';
  private static final String NON_READER_LAST_NAME = '결과수신테스트SV권한없음';

  // DESC: 사용자 · 권한 집합 할당은 설정(setup) 개체끼리라 한 트랜잭션에 둔다. 업무 데이터는 각 테스트에서 만든다
  @TestSetup
  static void createUsers() {
    User integrationUser = TestDataFactory.createIntegrationUser(
      INTEGRATION_LAST_NAME,
      false
    );
    User reader = TestDataFactory.createSvUser(READER_LAST_NAME, false);
    User nonReader = TestDataFactory.createSvUser(NON_READER_LAST_NAME, false);
    insert new List<User>{ integrationUser, reader, nonReader };
    insert new List<PermissionSetAssignment>{
      assignmentOf(integrationUser.Id, 'LogisticsResultAccess'),
      assignmentOf(reader.Id, 'PenaltyLogisticsAccess')
    };
  }

  // 증명: 다른 사람 소유 페널티의 반영 완료 회신을 연동 사용자가 받으면 수신 로그가 정의대로 남고(소유자 = 로그를 읽을 수 있는
  //       페널티 소유자), 응답 본문이 로그에 그대로 기록되며, 페널티는 수정되지 않는다
  @IsTest
  static void receive_applied_recordsInboundLogWithoutTouchingPenalty() {
    User reader = userNamed(READER_LAST_NAME);
    Penalty__c penalty = insertPenalty(reader.Id);
    insertSentLog(
      penalty,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      REQUEST_NO
    );
    Assert.isFalse(
      hasReadAccess(userNamed(INTEGRATION_LAST_NAME).Id, penalty.Id),
      '전제: 연동 사용자는 이 페널티에 공유 경로가 없다'
    );
    String body = JSON.serialize(payloadOf(penalty.Id, 'APPLIED'));

    Test.startTest();
    ApiResponse res = postAsIntegrationUser(body);
    Test.stopTest();

    Assert.areEqual(200, res.statusCode, '정상 회신은 200');
    Assert.areEqual(
      LogisticsResultService.RESPONSE_RECORDED,
      res.text('result'),
      '처음 받은 회신은 RECORDED'
    );
    IntegrationLog__c log = getOnlyReceipt();
    Assert.areEqual(log.Name, res.text('logNo'), '응답의 로그 번호');
    Assert.areEqual(penalty.Id, log.Penalty__c, '페널티 연결');
    Assert.areEqual(
      String.valueOf(penalty.Id),
      log.CorrelationId__c,
      '상관 ID'
    );
    Assert.areEqual(
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      log.Status__c,
      '상태 성공'
    );
    Assert.areEqual(REQUEST_NO, log.RequestNo__c, '접수번호');
    Assert.areEqual(
      LogisticsResultService.RESULT_APPLIED,
      log.ApplyResult__c,
      'APPLIED → 반영완료'
    );
    Assert.areEqual(200, log.StatusCode__c, '상태코드 200');
    Assert.areEqual(body, log.RequestBody__c, '요청 본문 그대로');
    Assert.areEqual(
      res.body,
      JSON.deserializeUntyped(log.ResponseBody__c),
      '응답 본문(로그 번호 포함) 그대로'
    );
    Assert.areEqual(
      reader.Id,
      log.OwnerId,
      '로그를 읽을 수 있는 페널티 소유자가 로그 소유자'
    );
    Assert.areEqual(
      userNamed(INTEGRATION_LAST_NAME).Id,
      log.CreatedById,
      '기록은 연동 사용자가 남긴다'
    );
    assertPenaltyUntouched(
      penalty.Id,
      LogisticsNotifyService.PENALTY_STATUS_APPROVED
    );
  }

  // 증명: 반영 거절 회신은 반영거절로 남고 사유는 요청 본문에 담긴다. 페널티 소유자가 로그를 못 읽으면 소유자는 연동 사용자
  @IsTest
  static void receive_rejectedOwnerCannotReadLogs_logOwnedByIntegrationUser() {
    Penalty__c penalty = insertPenalty(userNamed(NON_READER_LAST_NAME).Id);
    insertSentLog(
      penalty,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      REQUEST_NO
    );

    Test.startTest();
    ApiResponse res = postAsIntegrationUser(
      JSON.serialize(payloadOf(penalty.Id, 'REJECTED'))
    );
    Test.stopTest();

    Assert.areEqual(200, res.statusCode, '거절 회신도 기록되면 200');
    IntegrationLog__c log = getOnlyReceipt();
    Assert.areEqual(
      LogisticsResultService.RESULT_REJECTED,
      log.ApplyResult__c,
      'REJECTED → 반영거절'
    );
    Assert.isTrue(
      log.RequestBody__c.contains(REJECT_MESSAGE),
      '거절 사유는 요청 본문에 남는다'
    );
    Assert.areEqual(
      userNamed(INTEGRATION_LAST_NAME).Id,
      log.OwnerId,
      '로그 읽기 권한 없는 소유자는 지정하지 않는다(TRANSFER_REQUIRES_READ) — 기본 소유자'
    );
    assertPenaltyUntouched(
      penalty.Id,
      LogisticsNotifyService.PENALTY_STATUS_APPROVED
    );
  }

  // 증명: 페널티 소유자가 비활성이면(퇴사 등) 로그 권한이 있어도 소유자로 지정하지 않아 기록이 실패하지 않는다
  @IsTest
  static void receive_inactiveOwner_logOwnedByIntegrationUser() {
    User reader = userNamed(READER_LAST_NAME);
    Penalty__c penalty = insertPenalty(reader.Id);
    insertSentLog(
      penalty,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      REQUEST_NO
    );
    // NOTE: 사용자(설정 개체) 갱신을 업무 데이터 insert와 분리해 Mixed DML을 피한다
    System.runAs(new User(Id = UserInfo.getUserId())) {
      update new User(Id = reader.Id, IsActive = false);
    }

    Test.startTest();
    ApiResponse res = postAsIntegrationUser(
      JSON.serialize(payloadOf(penalty.Id, 'APPLIED'))
    );
    Test.stopTest();

    Assert.areEqual(
      200,
      res.statusCode,
      '비활성 소유자여도 기록된다(INACTIVE_OWNER_OR_USER 아님)'
    );
    Assert.areEqual(
      userNamed(INTEGRATION_LAST_NAME).Id,
      getOnlyReceipt().OwnerId,
      '비활성 사용자는 소유자로 지정하지 않는다 — 기본 소유자'
    );
  }

  // 증명: 같은 상관 ID · 접수번호 · 결과가 다시 오면 기록하지 않고 200 UNCHANGED와 처음 로그 번호를 돌려준다
  @IsTest
  static void receive_sameResultTwice_secondIsUnchanged() {
    Penalty__c penalty = insertPenalty(userNamed(READER_LAST_NAME).Id);
    insertSentLog(
      penalty,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      REQUEST_NO
    );
    String body = JSON.serialize(payloadOf(penalty.Id, 'APPLIED'));

    Test.startTest();
    ApiResponse first = postAsIntegrationUser(body);
    ApiResponse second = postAsIntegrationUser(body);
    Test.stopTest();

    Assert.areEqual(200, second.statusCode, '재수신도 200');
    Assert.areEqual(
      LogisticsResultService.RESPONSE_UNCHANGED,
      second.text('result'),
      '같은 회신의 재전송은 UNCHANGED'
    );
    Assert.areEqual(
      first.text('logNo'),
      second.text('logNo'),
      '처음 기록한 로그 번호'
    );
    Assert.areEqual(1, countReceipts(), '수신 로그는 1건만');
  }

  // 증명: 이미 다른 결과로 받은 건에 반대 결과가 오면 409로 거절하고 처음 기록을 바꾸지 않는다
  @IsTest
  static void receive_differentResultAfterRecorded_isConflict() {
    Penalty__c penalty = insertPenalty(userNamed(READER_LAST_NAME).Id);
    insertSentLog(
      penalty,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      REQUEST_NO
    );

    Test.startTest();
    ApiResponse first = postAsIntegrationUser(
      JSON.serialize(payloadOf(penalty.Id, 'APPLIED'))
    );
    ApiResponse second = postAsIntegrationUser(
      JSON.serialize(payloadOf(penalty.Id, 'REJECTED'))
    );
    Test.stopTest();

    Assert.areEqual(409, second.statusCode, '다른 결과로 이미 수신됨은 409');
    Assert.isTrue(
      second.text('error').contains(first.text('logNo')),
      '오류에 처음 로그 번호가 있어 사람이 확인할 수 있다: ' +
      second.text('error')
    );
    Assert.areEqual(1, countReceipts(), '수신 로그는 처음 1건만');
    Assert.areEqual(
      LogisticsResultService.RESULT_APPLIED,
      getOnlyReceipt().ApplyResult__c,
      '처음 결과는 그대로'
    );
    assertPenaltyUntouched(
      penalty.Id,
      LogisticsNotifyService.PENALTY_STATUS_APPROVED
    );
  }

  // 증명: 형식 오류는 모두 400이고 아무것도 기록하지 않는다
  @IsTest
  static void receive_invalidRequests_areBadRequest() {
    Penalty__c penalty = insertPenalty(userNamed(READER_LAST_NAME).Id);
    insertSentLog(
      penalty,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      REQUEST_NO
    );
    Map<String, Blob> bodiesByCase = new Map<String, Blob>{
      '빈 본문' => null,
      'JSON 아님' => Blob.valueOf('not json'),
      'JSON 배열' => Blob.valueOf('[]'),
      // NOTE: 0xFF 1바이트 — UTF-8로 읽을 수 없는 본문
      'UTF-8 아님' => EncodingUtil.base64Decode('/w=='),
      'correlationId 누락' => bodyWith(penalty.Id, 'correlationId', null),
      'correlationId 15자' => bodyWith(
        penalty.Id,
        'correlationId',
        String.valueOf(penalty.Id).left(15)
      ),
      'correlationId 다른 오브젝트' => bodyWith(
        penalty.Id,
        'correlationId',
        String.valueOf(penalty.Franchise__c)
      ),
      'correlationId 숫자' => bodyWith(
        penalty.Id,
        'correlationId',
        123456789012345678L
      ),
      'correlationId 18자지만 Id 아님' => bodyWith(
        penalty.Id,
        'correlationId',
        'x'.repeat(18)
      ),
      'requestNo 누락' => bodyWith(penalty.Id, 'requestNo', null),
      'requestNo 숫자' => bodyWith(penalty.Id, 'requestNo', 123),
      'requestNo 21자' => bodyWith(
        penalty.Id,
        'requestNo',
        'SR-' + '0'.repeat(18)
      ),
      'status 없는 값' => bodyWith(penalty.Id, 'status', 'DONE'),
      'status 소문자' => bodyWith(penalty.Id, 'status', 'applied'),
      'REJECTED인데 message 없음' => bodyWith(penalty.Id, 'status', 'REJECTED'),
      'processedAt 누락' => bodyWith(penalty.Id, 'processedAt', null),
      'processedAt 형식' => bodyWith(
        penalty.Id,
        'processedAt',
        '2026-10-18 10:00:00'
      ),
      'processedAt 없는 일시' => bodyWith(
        penalty.Id,
        'processedAt',
        '2026-13-40T25:00:00Z'
      ),
      'message 256자' => bodyWith(penalty.Id, 'message', 'x'.repeat(256))
    };

    Map<String, ApiResponse> responsesByCase = new Map<String, ApiResponse>();
    Test.startTest();
    for (String caseName : bodiesByCase.keySet()) {
      responsesByCase.put(
        caseName,
        postAsIntegrationUser(bodiesByCase.get(caseName))
      );
    }
    Test.stopTest();

    for (String caseName : responsesByCase.keySet()) {
      ApiResponse res = responsesByCase.get(caseName);
      Assert.areEqual(
        400,
        res.statusCode,
        caseName + ' → 400 (' + res.body + ')'
      );
      Assert.isTrue(
        String.isNotBlank(res.text('error')),
        caseName + ' → 오류 사유가 있다'
      );
    }
    Assert.areEqual(0, countReceipts(), '형식 오류는 기록하지 않는다');
  }

  // 증명: 페널티 Id 형식이지만 페널티가 없으면(삭제됨) 404
  @IsTest
  static void receive_deletedPenalty_isNotFound() {
    Penalty__c penalty = insertPenalty(userNamed(READER_LAST_NAME).Id);
    insertSentLog(
      penalty,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      REQUEST_NO
    );
    delete penalty;

    Test.startTest();
    ApiResponse res = postAsIntegrationUser(
      JSON.serialize(payloadOf(penalty.Id, 'APPLIED'))
    );
    Test.stopTest();

    Assert.areEqual(404, res.statusCode, '페널티 없음은 404');
    Assert.areEqual(0, countReceipts(), '기록하지 않는다');
  }

  // 증명: 공급 제한 · 승인이 아닌 페널티(승인 전 · 다른 유형)의 회신은 409
  @IsTest
  static void receive_penaltyNotApprovedSupplyRestriction_isConflict() {
    Id ownerId = userNamed(READER_LAST_NAME).Id;
    List<Penalty__c> penalties = newPenalties(2, ownerId);
    Penalty__c pending = penalties[0];
    pending.Status__c = '승인대기';
    Penalty__c warning = penalties[1];
    warning.PenaltyType__c = '경고';
    insert penalties;
    insertSentLog(
      pending,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      REQUEST_NO
    );
    insertSentLog(
      warning,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      REQUEST_NO
    );

    Test.startTest();
    ApiResponse pendingRes = postAsIntegrationUser(
      JSON.serialize(payloadOf(pending.Id, 'APPLIED'))
    );
    ApiResponse warningRes = postAsIntegrationUser(
      JSON.serialize(payloadOf(warning.Id, 'APPLIED'))
    );
    Test.stopTest();

    Assert.areEqual(409, pendingRes.statusCode, '승인 전 페널티는 409');
    Assert.areEqual(
      409,
      warningRes.statusCode,
      '공급 제한이 아닌 페널티는 409'
    );
    Assert.isTrue(
      pendingRes.text('error').contains('승인 상태가 아님'),
      '사유: ' + pendingRes.text('error')
    );
    Assert.areEqual(0, countReceipts(), '기록하지 않는다');
    assertPenaltyUntouched(pending.Id, '승인대기');
  }

  // 증명: 같은 상관 ID의 IF-001 송신이 성공하지 않았거나(재시도대기) 접수번호가 다르면 409
  @IsTest
  static void receive_withoutMatchingSuccessfulSend_isConflict() {
    Id ownerId = userNamed(READER_LAST_NAME).Id;
    List<Penalty__c> penalties = newPenalties(2, ownerId);
    insert penalties;
    Penalty__c retrying = penalties[0];
    Penalty__c otherRequestNo = penalties[1];
    insertSentLog(retrying, LogisticsNotifyService.LOG_STATUS_RETRY, null);
    insertSentLog(
      otherRequestNo,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      'SR-000999'
    );

    Test.startTest();
    ApiResponse retryingRes = postAsIntegrationUser(
      JSON.serialize(payloadOf(retrying.Id, 'APPLIED'))
    );
    ApiResponse otherRequestNoRes = postAsIntegrationUser(
      JSON.serialize(payloadOf(otherRequestNo.Id, 'APPLIED'))
    );
    Test.stopTest();

    Assert.areEqual(409, retryingRes.statusCode, '송신 성공 기록이 없으면 409');
    Assert.isTrue(
      retryingRes.text('error').contains('송신 성공 기록 없음'),
      '사유: ' + retryingRes.text('error')
    );
    Assert.areEqual(409, otherRequestNoRes.statusCode, '접수번호가 다르면 409');
    Assert.isTrue(
      otherRequestNoRes.text('error').contains('접수번호'),
      '사유: ' + otherRequestNoRes.text('error')
    );
    Assert.areEqual(0, countReceipts(), '기록하지 않는다');
  }

  // 증명: 기록 도중 예기치 못한 예외가 나면 500으로 답하고, 이미 insert한 수신 로그까지 되돌린다(반쯤 남지 않음).
  //       응답 본문에는 오류 문구만 있고 예외 클래스 · 줄 번호가 없다
  @IsTest
  static void receive_unexpectedFailureAfterInsert_rollsBackAndReturns500() {
    Penalty__c penalty = insertPenalty(userNamed(READER_LAST_NAME).Id);
    insertSentLog(
      penalty,
      LogisticsNotifyService.LOG_STATUS_SUCCESS,
      REQUEST_NO
    );
    LogisticsResultService.failAfterInsertForTest = true;

    Test.startTest();
    ApiResponse res = postAsIntegrationUser(
      JSON.serialize(payloadOf(penalty.Id, 'APPLIED'))
    );
    Test.stopTest();

    Assert.areEqual(500, res.statusCode, '500 — 물류 org가 재시도한다');
    Assert.areEqual(
      new Set<String>{ 'error' },
      res.body.keySet(),
      '오류 문구만 싣는다'
    );
    Assert.isFalse(
      res.text('error').contains('Exception') ||
      res.text('error').contains('line'),
      '예외 클래스 · 줄 번호를 내보내지 않는다: ' + res.text('error')
    );
    Assert.areEqual(
      0,
      countReceipts(),
      '롤백 — insert한 수신 로그가 남지 않는다'
    );
    assertPenaltyUntouched(
      penalty.Id,
      LogisticsNotifyService.PENALTY_STATUS_APPROVED
    );
  }

  // ------------------------------------------------------------------ helpers

  // DESC: 응답 상태코드와 JSON 본문
  private class ApiResponse {
    Integer statusCode;
    Map<String, Object> body;

    ApiResponse(RestResponse res) {
      statusCode = res.statusCode;
      body = (Map<String, Object>) JSON.deserializeUntyped(
        res.responseBody.toString()
      );
    }

    String text(String key) {
      return (String) body.get(key);
    }
  }

  private static ApiResponse postAsIntegrationUser(String body) {
    return postAsIntegrationUser(Blob.valueOf(body));
  }

  private static ApiResponse postAsIntegrationUser(Blob body) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/v1/supply-restriction-results';
    req.httpMethod = 'POST';
    req.requestBody = body;
    RestContext.request = req;
    RestContext.response = new RestResponse();
    System.runAs(userNamed(INTEGRATION_LAST_NAME)) {
      LogisticsResultRestResource.receiveResult();
    }
    return new ApiResponse(RestContext.response);
  }

  // DESC: 정상 회신 본문. REJECTED면 사유를 채운다
  private static Map<String, Object> payloadOf(Id penaltyId, String status) {
    return new Map<String, Object>{
      'correlationId' => String.valueOf(penaltyId),
      'requestNo' => REQUEST_NO,
      'status' => status,
      'processedAt' => PROCESSED_AT,
      'message' => status == 'REJECTED' ? REJECT_MESSAGE : null
    };
  }

  // DESC: 정상 반영 완료 본문에서 한 항목만 바꾼다(null이면 뺀다)
  private static Blob bodyWith(Id penaltyId, String key, Object value) {
    Map<String, Object> payload = payloadOf(penaltyId, 'APPLIED');
    if (value == null) {
      payload.remove(key);
    } else {
      payload.put(key, value);
    }
    return Blob.valueOf(JSON.serialize(payload));
  }

  private static Penalty__c insertPenalty(Id ownerId) {
    Penalty__c penalty = newPenalties(1, ownerId)[0];
    insert penalty;
    return penalty;
  }

  // DESC: 승인된 공급 제한 페널티를 가맹점마다 1건씩 만든다(insert 전). 준비 사용자(관리자)가 insert하고 소유자만 지정한다 —
  //       연동 사용자에게는 공유 경로가 없다. 다른 유형 · 상태가 필요하면 insert 전에 바꾼다
  // NOTE: createFranchises는 호출마다 사업자번호를 0번부터 매겨 한 테스트에서 두 번 부르면 중복 규칙에 걸린다 → 한 번에 만든다
  private static List<Penalty__c> newPenalties(Integer count, Id ownerId) {
    List<Penalty__c> penalties = TestDataFactory.createSupplyRestrictionPenalties(
      TestDataFactory.createFranchises(count, true),
      false
    );
    for (Penalty__c penalty : penalties) {
      penalty.OwnerId = ownerId;
    }
    return penalties;
  }

  private static void insertSentLog(
    Penalty__c penalty,
    String status,
    String requestNo
  ) {
    IntegrationLog__c log = TestDataFactory.createLogisticsNotifyLogs(
      new List<Penalty__c>{ penalty },
      status,
      1,
      false
    )[0];
    log.RequestNo__c = requestNo;
    insert as system log;
  }

  // DESC: 수신부가 페널티를 수정했다면 마지막 수정자가 연동 사용자로 바뀐다
  private static void assertPenaltyUntouched(
    Id penaltyId,
    String expectedStatus
  ) {
    Penalty__c penalty = [
      SELECT Status__c, LastModifiedById
      FROM Penalty__c
      WHERE Id = :penaltyId
    ];
    Assert.areEqual(
      UserInfo.getUserId(),
      penalty.LastModifiedById,
      '페널티는 수정하지 않는다 — 마지막 수정자는 준비한 사용자 그대로'
    );
    Assert.areEqual(expectedStatus, penalty.Status__c, '페널티 상태 그대로');
  }

  private static IntegrationLog__c getOnlyReceipt() {
    return [
      SELECT
        Name,
        Penalty__c,
        CorrelationId__c,
        Status__c,
        RequestNo__c,
        ApplyResult__c,
        StatusCode__c,
        RequestBody__c,
        ResponseBody__c,
        OwnerId,
        CreatedById
      FROM IntegrationLog__c
      WHERE
        InterfaceId__c = :LogisticsResultService.INTERFACE_ID
        AND Direction__c = :LogisticsResultService.DIRECTION_INBOUND
    ];
  }

  private static Integer countReceipts() {
    return [
      SELECT COUNT()
      FROM IntegrationLog__c
      WHERE InterfaceId__c = :LogisticsResultService.INTERFACE_ID
    ];
  }

  private static Boolean hasReadAccess(Id userId, Id recordId) {
    return [
      SELECT RecordId, HasReadAccess
      FROM UserRecordAccess
      WHERE UserId = :userId AND RecordId = :recordId
    ]
    .HasReadAccess;
  }

  private static User userNamed(String lastName) {
    return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
  }

  private static PermissionSetAssignment assignmentOf(
    Id userId,
    String permissionSetName
  ) {
    return new PermissionSetAssignment(
      AssigneeId = userId,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = :permissionSetName
      ]
      .Id
    );
  }
}
