/* ======================================================================================
 * @description : 출고 제한 처리 → IF-004 회신(트리거 · Queueable · 전송 결과 기록)을 검증하는 테스트 클래스
 * @testTarget  : SupplyRestriction.trigger, SupplyRestrictionTriggerHandler, SupplyRestrictionResultQueueable,
 *                SupplyRestrictionResultService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 200 · 409 · 400 · 시간 초과, 200건 enqueue 1번, 권한 없는 사용자 runAs(Step 7-B)
 * ======================================================================================
 *  @see         : SupplyRestrictionResultMock.cls
 *  @note        : 처리는 상태 update(트리거) → Queueable(Test.stopTest()) 순서로 돈다. Test.setMock은 Test.startTest() 앞에서 호출한다.
 *                 TestDataFactory는 kai-dev 패키지(force-app) 소속이라 물류 org에 없어 이 클래스의 도우미로 만든다
 * ======================================================================================*/
@IsTest
private class SupplyRestrictionResultQueueableTest {
  private static final String RECORDED_BODY = '{"result":"RECORDED","logNo":"LOG-000002"}';
  private static final String REJECT_MESSAGE = '매장 폐점 예정으로 반영 불가';
  private static final Pattern ISO_UTC = Pattern.compile(
    '\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z'
  );

  // 증명: 접수 → 반영완료로 바꾸면 처리 일시가 채워지고, 회신이 정의대로 나가며(상관 ID · 접수번호 · APPLIED · ISO UTC),
  //       200이면 전송완료로 기록된다
  @IsTest
  static void resolveApplied_ok_callbackSent() {
    SupplyRestriction__c restriction = insertRestrictions(1)[0];
    SupplyRestrictionResultMock mock = new SupplyRestrictionResultMock(
      200,
      RECORDED_BODY
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    restriction.Status__c = SupplyRestrictionService.STATUS_APPLIED;
    update restriction;
    Test.stopTest();

    SupplyRestriction__c saved = getRestriction(restriction.Id);
    Assert.areEqual(
      SupplyRestrictionResultService.CALLBACK_SENT,
      saved.CallbackStatus__c,
      '200이면 전송완료'
    );
    Assert.isNull(saved.CallbackError__c, '전송완료면 회신 오류 없음');
    Assert.isNotNull(saved.ProcessedAt__c, '처리 일시가 비어 있으면 채운다');
    Assert.areEqual(1, mock.requestBodies.size(), '회신 1번');
    Map<String, Object> payload = mock.lastPayload();
    Assert.areEqual(
      saved.CorrelationId__c,
      payload.get('correlationId'),
      '상관 ID'
    );
    Assert.areEqual(
      saved.Name,
      payload.get('requestNo'),
      '접수번호 = 레코드 이름'
    );
    Assert.areEqual('APPLIED', payload.get('status'), '반영완료 → APPLIED');
    Assert.areEqual(
      saved.ProcessedAt__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
      payload.get('processedAt'),
      '처리 일시를 UTC로'
    );
    Assert.isTrue(
      ISO_UTC.matcher((String) payload.get('processedAt')).matches(),
      'ISO-8601 UTC 형식: ' + payload.get('processedAt')
    );
  }

  // 증명: 반영거절은 REJECTED와 거절 사유(결과 메시지)를 보낸다. 409면 전송실패 + 사유가 회신 오류에 남고,
  //       담당자가 쓴 결과 메시지는 그대로다. 담당자가 넣은 처리 일시도 그대로 보낸다
  @IsTest
  static void resolveRejected_conflict_failureRecordedAndMessageKept() {
    Datetime processedAt = Datetime.newInstanceGmt(2026, 10, 18, 1, 0, 0);
    SupplyRestriction__c restriction = insertRestrictions(1)[0];
    SupplyRestrictionResultMock mock = new SupplyRestrictionResultMock(
      409,
      '{"error":"이미 다른 결과로 수신됨: LOG-000001 (반영완료)"}'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    restriction.Status__c = SupplyRestrictionService.STATUS_REJECTED;
    restriction.ResultMessage__c = REJECT_MESSAGE;
    restriction.ProcessedAt__c = processedAt;
    update restriction;
    Test.stopTest();

    SupplyRestriction__c saved = getRestriction(restriction.Id);
    Assert.areEqual(
      SupplyRestrictionResultService.CALLBACK_FAILED,
      saved.CallbackStatus__c,
      '200이 아니면 전송실패'
    );
    Assert.areEqual(
      'HTTP 409 이미 다른 결과로 수신됨: LOG-000001 (반영완료)',
      saved.CallbackError__c,
      '상태코드와 응답 오류를 회신 오류에 남긴다'
    );
    Assert.areEqual(
      REJECT_MESSAGE,
      saved.ResultMessage__c,
      '결과 메시지(거절 사유)는 덮어쓰지 않는다'
    );
    Assert.areEqual(
      processedAt,
      saved.ProcessedAt__c,
      '담당자가 넣은 처리 일시는 바꾸지 않는다'
    );
    Map<String, Object> payload = mock.lastPayload();
    Assert.areEqual('REJECTED', payload.get('status'), '반영거절 → REJECTED');
    Assert.areEqual(
      REJECT_MESSAGE,
      payload.get('message'),
      '거절 사유를 message로'
    );
    Assert.areEqual(
      '2026-10-18T01:00:00Z',
      payload.get('processedAt'),
      '담당자가 넣은 처리 일시'
    );
  }

  // 증명: 400이면 전송실패 + 응답 오류. JSON이 아닌 응답은 본문을 그대로 남긴다
  @IsTest
  static void resolve_badRequest_failureRecorded() {
    List<SupplyRestriction__c> restrictions = insertRestrictions(1);
    Test.setMock(
      HttpCalloutMock.class,
      new SupplyRestrictionResultMock(400, 'Bad Request')
    );

    Test.startTest();
    resolveAll(restrictions, SupplyRestrictionService.STATUS_APPLIED);
    Test.stopTest();

    SupplyRestriction__c saved = getRestriction(restrictions[0].Id);
    Assert.areEqual(
      SupplyRestrictionResultService.CALLBACK_FAILED,
      saved.CallbackStatus__c,
      '400은 전송실패'
    );
    Assert.areEqual(
      'HTTP 400 Bad Request',
      saved.CallbackError__c,
      '응답 본문 그대로'
    );
  }

  // 증명: 시간 초과(응답 없음)도 전송실패 + 연결 실패 사유. 자동 재시도는 하지 않는다(다음 job 없음)
  @IsTest
  static void resolve_timeout_failureRecordedWithoutRetry() {
    List<SupplyRestriction__c> restrictions = insertRestrictions(1);
    SupplyRestrictionResultMock mock = SupplyRestrictionResultMock.failing(
      'Read timed out'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    resolveAll(restrictions, SupplyRestrictionService.STATUS_APPLIED);
    Test.stopTest();

    SupplyRestriction__c saved = getRestriction(restrictions[0].Id);
    Assert.areEqual(
      SupplyRestrictionResultService.CALLBACK_FAILED,
      saved.CallbackStatus__c,
      '시간 초과는 전송실패'
    );
    Assert.areEqual(
      '연결 실패: Read timed out',
      saved.CallbackError__c,
      '연결 실패 사유'
    );
    Assert.areEqual(1, mock.requestBodies.size(), '한 번만 보낸다');
    Assert.isNull(
      SupplyRestrictionResultQueueable.chainedIdsInTest,
      '자동 재시도 job을 넣지 않는다'
    );
  }

  // 증명: 거절 사유 없는 반영거절은 검증 규칙이 저장을 막는다 — 상태가 그대로라 회신 job도 생기지 않는다
  @IsTest
  static void resolveRejectedWithoutMessage_blockedByValidationRule() {
    SupplyRestriction__c restriction = insertRestrictions(1)[0];

    Test.startTest();
    Database.SaveResult result = Database.update(
      new SupplyRestriction__c(
        Id = restriction.Id,
        Status__c = SupplyRestrictionService.STATUS_REJECTED
      ),
      false
    );
    Integer jobsEnqueued = Limits.getQueueableJobs();
    Test.stopTest();

    Assert.isFalse(
      result.isSuccess(),
      '거절 사유 없이 반영거절로 저장할 수 없다'
    );
    Assert.isTrue(
      result.getErrors()[0].getMessage().contains('결과 메시지'),
      '검증 규칙 오류: ' + result.getErrors()[0].getMessage()
    );
    Assert.areEqual(0, jobsEnqueued, '저장되지 않았으니 회신 job도 없다');
    Assert.areEqual(
      SupplyRestrictionService.STATUS_RECEIVED,
      [SELECT Status__c FROM SupplyRestriction__c WHERE Id = :restriction.Id]
      .Status__c,
      '처리 상태는 접수 그대로'
    );
  }

  // 증명: 200건을 한 번에 처리해도 enqueue는 1번. 첫 job이 10건을 보내고 남은 190건을 다음 job으로 넘긴다
  @IsTest
  static void resolveBulk200_enqueuesOnceAndSendsTenPerJob() {
    List<SupplyRestriction__c> restrictions = insertRestrictions(200);
    SupplyRestrictionResultMock mock = new SupplyRestrictionResultMock(
      200,
      RECORDED_BODY
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    resolveAll(restrictions, SupplyRestrictionService.STATUS_APPLIED);
    Integer jobsEnqueued = Limits.getQueueableJobs();
    Test.stopTest();

    Assert.areEqual(1, jobsEnqueued, '200건이어도 Queueable은 1번');
    Assert.areEqual(10, mock.requestBodies.size(), 'job 하나가 10건 보낸다');
    Assert.areEqual(
      10,
      countByCallbackStatus(SupplyRestrictionResultService.CALLBACK_SENT),
      '10건 전송완료'
    );
    Assert.areEqual(
      190,
      countByCallbackStatus(SupplyRestrictionService.CALLBACK_NOT_SENT),
      '190건은 다음 job 대기'
    );
    Assert.areEqual(
      190,
      SupplyRestrictionResultQueueable.chainedIdsInTest.size(),
      '남은 190건을 다음 job으로'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM SupplyRestriction__c WHERE ProcessedAt__c = NULL],
      '200건 모두 처리 일시가 채워진다'
    );
  }

  // 증명: 「접수 → 반영완료 · 반영거절」이 아닌 변경(접수 그대로 · 반영완료 → 반영거절)은 회신하지 않는다
  @IsTest
  static void updateWithoutResolution_notEnqueued() {
    SupplyRestriction__c stillReceived = insertRestrictions(1)[0];
    SupplyRestriction__c alreadyApplied = insertResolved(
      1,
      SupplyRestrictionResultService.CALLBACK_SENT
    )[0];

    Test.startTest();
    stillReceived.ResultMessage__c = '확인 중';
    alreadyApplied.Status__c = SupplyRestrictionService.STATUS_REJECTED;
    alreadyApplied.ResultMessage__c = REJECT_MESSAGE;
    update new List<SupplyRestriction__c>{ stillReceived, alreadyApplied };
    Integer jobsEnqueued = Limits.getQueueableJobs();
    Test.stopTest();

    Assert.areEqual(
      0,
      jobsEnqueued,
      '처리 상태 전환이 아니면 enqueue하지 않는다'
    );
    Assert.isNull(
      getRestriction(stillReceived.Id).ProcessedAt__c,
      '접수 그대로면 처리 일시를 채우지 않는다'
    );
  }

  // 증명: 「점검 회신」이 없는 사용자(출고 제한 관리만 있음)가 처리하면 Queueable이 그 사용자 권한으로 돌아
  //       콜아웃이 실패하고, 회신 오류 편집 권한이 없어도 전송실패 + 사유가 기록된다
  @IsTest
  static void resolvedByUserWithoutCallbackPermission_failureRecorded() {
    User handler = insertHandlerWithoutCallbackPermission();
    List<SupplyRestriction__c> restrictions = insertRestrictions(1);
    // NOTE: Mock은 주체 접근을 검사하지 않는다 — 운영에서 나는 연결 실패를 메시지로 흉내 낸다
    Test.setMock(
      HttpCalloutMock.class,
      SupplyRestrictionResultMock.failing(
        '외부 자격 증명 주체 접근 없음(테스트 흉내)'
      )
    );

    System.runAs(handler) {
      Assert.isFalse(
        Schema.SObjectType.SupplyRestriction__c.fields.CallbackError__c.isUpdateable(),
        '전제: 이 사용자는 회신 오류를 편집할 수 없다'
      );
      Test.startTest();
      resolveAll(restrictions, SupplyRestrictionService.STATUS_APPLIED);
      Test.stopTest();
    }

    SupplyRestriction__c saved = getRestriction(restrictions[0].Id);
    Assert.areEqual(
      SupplyRestrictionResultService.CALLBACK_FAILED,
      saved.CallbackStatus__c,
      '권한 없는 사용자의 회신은 전송실패로 남는다'
    );
    Assert.isTrue(
      saved.CallbackError__c.startsWith('연결 실패: 외부 자격 증명'),
      '사유: ' + saved.CallbackError__c
    );
    Assert.areEqual(
      handler.Id,
      saved.LastModifiedById,
      'Queueable은 상태를 바꾼 사용자로 돈다'
    );
  }

  // 증명: 재전송(스크립트가 하는 enqueue) — 전송실패 건은 다시 보내 전송완료가 되고, 이미 전송완료인 건은 보내지 않는다
  @IsTest
  static void resendFailedAndSent_onlyFailedIsSent() {
    SupplyRestriction__c failed = insertResolved(
      1,
      SupplyRestrictionResultService.CALLBACK_FAILED
    )[0];
    SupplyRestriction__c sent = insertRestrictionsAs(
      1,
      SupplyRestrictionService.STATUS_APPLIED,
      SupplyRestrictionResultService.CALLBACK_SENT,
      'a0BSENT'
    )[0];
    SupplyRestrictionResultMock mock = new SupplyRestrictionResultMock(
      200,
      RECORDED_BODY
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    System.enqueueJob(
      new SupplyRestrictionResultQueueable(new List<Id>{ failed.Id, sent.Id })
    );
    Test.stopTest();

    SupplyRestriction__c resent = getRestriction(failed.Id);
    Assert.areEqual(
      SupplyRestrictionResultService.CALLBACK_SENT,
      resent.CallbackStatus__c,
      '전송실패 건을 다시 보내면 전송완료'
    );
    Assert.isNull(resent.CallbackError__c, '회신 오류를 비운다');
    Assert.areEqual(
      1,
      mock.requestBodies.size(),
      '이미 전송완료인 건은 보내지 않는다'
    );
  }

  // 증명: 큐 밖에서 10건 넘게 실행하면 남은 건을 실제 다음 job으로 넣고, 그 job이 나머지를 보낸다
  @IsTest
  static void executeOutsideQueue_moreThanBatch_enqueuesNextJob() {
    List<Id> restrictionIds = new List<Id>();
    for (
      SupplyRestriction__c restriction : insertResolved(
        12,
        SupplyRestrictionService.CALLBACK_NOT_SENT
      )
    ) {
      restrictionIds.add(restriction.Id);
    }
    SupplyRestrictionResultMock mock = new SupplyRestrictionResultMock(
      200,
      RECORDED_BODY
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    new SupplyRestrictionResultQueueable(restrictionIds).execute(null);
    Integer jobsEnqueued = Limits.getQueueableJobs();
    Test.stopTest();

    Assert.areEqual(1, jobsEnqueued, '남은 2건을 다음 job으로');
    Assert.areEqual(
      12,
      mock.requestBodies.size(),
      '직접 실행 10건 + 다음 job 2건'
    );
    Assert.areEqual(
      12,
      countByCallbackStatus(SupplyRestrictionResultService.CALLBACK_SENT),
      '12건 모두 전송완료'
    );
  }

  // 증명: 보낼 건이 없으면(이미 전송완료) 콜아웃도 결과 기록도 하지 않는다
  @IsTest
  static void sendResults_alreadySent_nothingSent() {
    SupplyRestriction__c sent = insertResolved(
      1,
      SupplyRestrictionResultService.CALLBACK_SENT
    )[0];
    SupplyRestrictionResultMock mock = new SupplyRestrictionResultMock(
      200,
      RECORDED_BODY
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    SupplyRestrictionResultService.sendResults(new List<Id>{ sent.Id });
    Integer dmlStatements = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(0, mock.requestBodies.size(), '보내지 않는다');
    Assert.areEqual(0, dmlStatements, '기록할 결과도 없다');
  }

  // 증명: 상관 ID나 처리 일시가 없는 건은 보내지 않고(kai-dev가 400으로 거절할 요청) 전송실패 + 사유
  @IsTest
  static void sendResults_missingCorrelationIdOrProcessedAt_notSent() {
    List<SupplyRestriction__c> restrictions = insertResolved(
      2,
      SupplyRestrictionService.CALLBACK_NOT_SENT
    );
    // NOTE: 이미 반영완료인 건의 수정이라 트리거는 회신하지 않는다(처리 상태 전환 아님)
    restrictions[0].CorrelationId__c = null;
    restrictions[1].ProcessedAt__c = null;
    update restrictions;
    SupplyRestrictionResultMock mock = new SupplyRestrictionResultMock(
      200,
      RECORDED_BODY
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    SupplyRestrictionResultService.sendResults(
      new List<Id>{ restrictions[0].Id, restrictions[1].Id }
    );
    Test.stopTest();

    Assert.isTrue(
      getRestriction(restrictions[0].Id)
        .CallbackError__c.startsWith('상관 ID 없음'),
      '상관 ID 없음 사유'
    );
    Assert.areEqual(
      '처리 일시 없음',
      getRestriction(restrictions[1].Id).CallbackError__c,
      '처리 일시 없음 사유'
    );
    Assert.areEqual(
      2,
      countByCallbackStatus(SupplyRestrictionResultService.CALLBACK_FAILED),
      '둘 다 전송실패'
    );
    Assert.areEqual(
      0,
      mock.requestBodies.size(),
      '거절될 요청은 보내지 않는다'
    );
  }

  // ------------------------------------------------------------------ helpers

  // DESC: IF-001로 접수된 것과 같은 상태(접수 · 미전송 · 상관 ID 18자)의 출고 제한
  private static List<SupplyRestriction__c> insertRestrictions(Integer count) {
    return insertRestrictionsAs(
      count,
      SupplyRestrictionService.STATUS_RECEIVED,
      SupplyRestrictionService.CALLBACK_NOT_SENT,
      'a0BTEST'
    );
  }

  // DESC: 이미 반영완료로 처리된 출고 제한. 트리거는 update에만 있어 insert로는 회신 job이 생기지 않는다
  private static List<SupplyRestriction__c> insertResolved(
    Integer count,
    String callbackStatus
  ) {
    return insertRestrictionsAs(
      count,
      SupplyRestrictionService.STATUS_APPLIED,
      callbackStatus,
      'a0BDONE'
    );
  }

  // NOTE: 상관 ID는 Unique — 한 테스트에서 여러 번 부를 때는 접두어(7자)를 달리한다
  private static List<SupplyRestriction__c> insertRestrictionsAs(
    Integer count,
    String status,
    String callbackStatus,
    String correlationPrefix
  ) {
    List<SupplyRestriction__c> restrictions = new List<SupplyRestriction__c>();
    for (Integer i = 0; i < count; i++) {
      restrictions.add(
        new SupplyRestriction__c(
          CorrelationId__c = correlationPrefix +
            String.valueOf(i).leftPad(11, '0'),
          StoreCode__c = 'HK-' + String.valueOf(i).leftPad(4, '0'),
          StartDate__c = Date.newInstance(2026, 10, 20),
          EndDate__c = Date.newInstance(2026, 10, 27),
          Reason__c = '같은 항목 3회 연속 지적 (BR-08)',
          Status__c = status,
          ProcessedAt__c = status == SupplyRestrictionService.STATUS_RECEIVED
            ? null
            : Datetime.now(),
          CallbackStatus__c = callbackStatus,
          CallbackError__c = callbackStatus ==
            SupplyRestrictionResultService.CALLBACK_FAILED
            ? 'HTTP 500 (응답 본문 없음)'
            : null
        )
      );
    }
    insert restrictions;
    return restrictions;
  }

  // DESC: 화면에서 담당자가 하듯 처리 상태만 바꿔 저장한다 — 다른 필드를 함께 보내면 FLS(사용자 모드 DML)에 걸린다
  private static void resolveAll(
    List<SupplyRestriction__c> restrictions,
    String status
  ) {
    List<SupplyRestriction__c> changes = new List<SupplyRestriction__c>();
    for (SupplyRestriction__c restriction : restrictions) {
      changes.add(
        new SupplyRestriction__c(Id = restriction.Id, Status__c = status)
      );
    }
    update changes;
  }

  // DESC: 「출고 제한 관리」만 있고 「점검 회신」은 없는 물류 담당. 사용자 · 할당(설정 개체)은 runAs로 분리해 Mixed DML을 피한다
  private static User insertHandlerWithoutCallbackPermission() {
    User handler = new User(
      ProfileId = [
        SELECT Id
        FROM Profile
        WHERE Name = 'Minimum Access - Salesforce'
      ]
      .Id,
      LastName = '물류담당테스트',
      Alias = 'tlgh',
      Email = 'test.logistics.handler@example.com',
      // NOTE: 사용자명은 org 전체(다른 org 포함)에서 유일해야 해 난수를 붙인다
      Username = 'test.logistics.handler.' +
        String.valueOf(Crypto.getRandomInteger()).replace('-', '') +
        '@example.com',
      TimeZoneSidKey = 'Asia/Seoul',
      LocaleSidKey = 'ko_KR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'ko'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert handler;
      insert new PermissionSetAssignment(
        AssigneeId = handler.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'SupplyRestrictionManagement'
        ]
        .Id
      );
    }
    return handler;
  }

  private static SupplyRestriction__c getRestriction(Id restrictionId) {
    return [
      SELECT
        Name,
        CorrelationId__c,
        ProcessedAt__c,
        ResultMessage__c,
        CallbackStatus__c,
        CallbackError__c,
        LastModifiedById
      FROM SupplyRestriction__c
      WHERE Id = :restrictionId
    ];
  }

  private static Integer countByCallbackStatus(String callbackStatus) {
    return [
      SELECT COUNT()
      FROM SupplyRestriction__c
      WHERE CallbackStatus__c = :callbackStatus
    ];
  }
}
