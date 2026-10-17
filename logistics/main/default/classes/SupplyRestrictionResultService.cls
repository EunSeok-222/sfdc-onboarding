/* ======================================================================================
 * @description : 출고 제한 처리 결과를 송신 측(kai-dev)에 회신한다 (IF-004 송신) — 회신 준비 · 전송 · 결과 기록
 * @testClass   : SupplyRestrictionResultQueueableTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 200 전송완료 · 그 외 전송실패(사유 기록), 자동 재시도 없음(Step 7-B)
 * ======================================================================================
 *  @see         : SupplyRestrictionResultQueueable.cls, SupplyRestrictionTriggerHandler.cls, 인터페이스 정의서 V1.1 IF-004
 *  @note        : 가상 물류 시스템(hankki-logistics org) 소스다. kai-dev에는 배포하지 않는다.
 *                 상태를 바꾼 사용자 권한으로 돈다 — 콜아웃 주체 접근은 권한 집합 「점검 회신」, 출고 제한 조회는 WITH USER_MODE.
 *                 회신 결과(회신 상태 · 회신 오류)만 시스템 기록으로 as system 저장한다.
 *                 재시도는 2차 — 전송실패 건은 scripts/apex/supplyRestrictionResendResult.apex로 다시 보낸다
 * ======================================================================================*/
public with sharing class SupplyRestrictionResultService {
  public static final String ENDPOINT = 'callout:HankkiInspection/v1/supply-restriction-results';
  public static final String CALLBACK_SENT = '전송완료';
  public static final String CALLBACK_FAILED = '전송실패';

  // NOTE: 콜아웃 누적 120초 한도 ÷ 타임아웃 10초 = 한 번에 최대 10건. Queueable이 이 단위로 나눠 부른다
  public static final Integer BATCH_SIZE = 10;
  private static final Integer TIMEOUT_MS = 10000;
  private static final Integer HTTP_OK = 200;
  private static final Integer ERROR_MAX_LENGTH = 255;

  // NOTE: 처리 상태(화면 값) → 회신 status(영문 코드). kai-dev 수신부가 이 코드만 받는다
  private static final Map<String, String> RESULT_CODE_BY_STATUS = new Map<String, String>{
    SupplyRestrictionService.STATUS_APPLIED => 'APPLIED',
    SupplyRestrictionService.STATUS_REJECTED => 'REJECTED'
  };

  /**
   * @description : 회신 대상 처리 상태(반영완료 · 반영거절)인지.
   * @author      : 이은석(Kai) | 2026.10.18
   * @param status 처리 상태(Status__c)
   * @return Boolean
   **/
  public static Boolean isResolved(String status) {
    return RESULT_CODE_BY_STATUS.containsKey(status);
  }

  /**
   * @description : before update에서 부른다. 처리된 건의 처리 일시를 비어 있을 때만 채우고 회신 상태를 미전송으로 맞춘다.
   * @author      : 이은석(Kai) | 2026.10.18
   * @param resolvedRestrictions 「접수」에서 반영완료 · 반영거절로 바뀐 Trigger.new 레코드 (DML 없이 값만 바꾼다)
   **/
  public static void prepareCallbacks(
    List<SupplyRestriction__c> resolvedRestrictions
  ) {
    Datetime now = Datetime.now();
    for (SupplyRestriction__c restriction : resolvedRestrictions) {
      // NOTE: 담당자가 처리 일시를 직접 넣었으면 그 값을 보낸다
      if (restriction.ProcessedAt__c == null) {
        restriction.ProcessedAt__c = now;
      }
      restriction.CallbackStatus__c = SupplyRestrictionService.CALLBACK_NOT_SENT;
      restriction.CallbackError__c = null;
    }
  }

  /**
   * @description : 출고 제한의 처리 결과를 kai-dev에 보내고 회신 상태를 기록한다. 콜아웃을 모두 끝낸 뒤 update를 1번 한다.
   *                반영완료 · 반영거절이 아니거나 이미 전송완료인 건은 보내지 않는다.
   * @author      : 이은석(Kai) | 2026.10.18
   * @param restrictionIds 보낼 출고 제한 Id (최대 BATCH_SIZE건)
   **/
  public static void sendResults(List<Id> restrictionIds) {
    List<SupplyRestriction__c> results = new List<SupplyRestriction__c>();
    for (SupplyRestriction__c restriction : [
      SELECT
        Id,
        Name,
        CorrelationId__c,
        Status__c,
        ProcessedAt__c,
        ResultMessage__c
      FROM SupplyRestriction__c
      WHERE
        Id IN :restrictionIds
        AND Status__c IN :RESULT_CODE_BY_STATUS.keySet()
        AND CallbackStatus__c != :CALLBACK_SENT
      WITH USER_MODE
      LIMIT :BATCH_SIZE
    ]) {
      results.add(send(restriction));
    }
    if (results.isEmpty()) {
      return;
    }
    // WARN: 회신 상태 · 회신 오류는 사용자 입력이 아니라 시스템 기록이다 — 상태를 바꾼 사용자에게 두 필드의 편집 권한이
    //       없어도 남도록 as system. 이 update는 처리 상태를 바꾸지 않아 트리거가 다시 회신하지 않는다
    update as system results;
  }

  // DESC: 1건을 보내고 결과(회신 상태 · 회신 오류)만 담은 레코드를 돌려준다
  private static SupplyRestriction__c send(SupplyRestriction__c restriction) {
    SupplyRestriction__c result = new SupplyRestriction__c(Id = restriction.Id);
    String problem = validate(restriction);
    if (problem != null) {
      return failed(result, problem);
    }
    HttpRequest req = new HttpRequest();
    req.setEndpoint(ENDPOINT);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setTimeout(TIMEOUT_MS);
    req.setBody(buildPayload(restriction));
    try {
      HttpResponse res = new Http().send(req);
      if (res.getStatusCode() == HTTP_OK) {
        // NOTE: 200은 RECORDED(처음 기록) · UNCHANGED(이미 같은 결과로 기록됨) 모두 전송완료다
        result.CallbackStatus__c = CALLBACK_SENT;
        result.CallbackError__c = null;
        return result;
      }
      return failed(
        result,
        'HTTP ' + res.getStatusCode() + ' ' + readError(res.getBody())
      );
    } catch (CalloutException e) {
      // NOTE: 응답이 없는 실패 — 시간 초과 · 주소 · 인증 · 권한(외부 자격 증명 주체 접근 없음 등). 자동 재시도는 하지 않는다
      return failed(result, '연결 실패: ' + e.getMessage());
    }
  }

  // DESC: 보내도 kai-dev가 400으로 거절할 건은 보내지 않는다
  private static String validate(SupplyRestriction__c restriction) {
    if (String.isBlank(restriction.CorrelationId__c)) {
      return '상관 ID 없음 — IF-001로 접수된 건만 회신할 수 있음';
    }
    if (restriction.ProcessedAt__c == null) {
      return '처리 일시 없음';
    }
    // NOTE: 반영거절의 결과 메시지(거절 사유)는 검증 규칙 RejectedRequiresResultMessage가 저장 시점에 막는다
    return null;
  }

  // DESC: processedAt은 ISO-8601 UTC(예: 2026-10-18T01:00:00Z)
  private static String buildPayload(SupplyRestriction__c restriction) {
    return JSON.serialize(
      new Map<String, Object>{
        'correlationId' => restriction.CorrelationId__c,
        'requestNo' => restriction.Name,
        'status' => RESULT_CODE_BY_STATUS.get(restriction.Status__c),
        'processedAt' => restriction.ProcessedAt__c.formatGmt(
          'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
        ),
        'message' => restriction.ResultMessage__c
      }
    );
  }

  // NOTE: kai-dev 오류 응답은 {"error": "..."} — 형식이 다르면 본문을 그대로 쓴다
  private static String readError(String body) {
    try {
      Object error = ((Map<String, Object>) JSON.deserializeUntyped(body))
        .get('error');
      if (error != null) {
        return String.valueOf(error);
      }
    } catch (Exception e) {
      // NOTE: JSON이 아니거나 객체가 아니면 아래에서 본문을 그대로 쓴다
    }
    return String.isBlank(body) ? '(응답 본문 없음)' : body;
  }

  private static SupplyRestriction__c failed(
    SupplyRestriction__c result,
    String reason
  ) {
    result.CallbackStatus__c = CALLBACK_FAILED;
    result.CallbackError__c = reason.left(ERROR_MAX_LENGTH);
    return result;
  }
}
