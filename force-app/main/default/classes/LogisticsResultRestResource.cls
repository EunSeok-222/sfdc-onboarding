/* ======================================================================================
 * @description : 공급 제한 반영 결과 회신 수신 Apex REST 진입점 (IF-004, POST /services/apexrest/v1/supply-restriction-results)
 * @testClass   : LogisticsResultRestResourceTest
 * @layer       : RestResource
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 요청 본문을 LogisticsResultService에 넘기고 결과를 HTTP 응답으로 옮김(Step 7-A)
 * ======================================================================================
 *  @see         : LogisticsResultService.cls, 인터페이스 정의서 V1.1 IF-004
 *  @note        : 진입점은 HTTP 입출력만 다룬다. 검증 · 판정 · 기록 로직은 Service에 둔다.
 *                 호출 권한은 권한 집합 「물류 결과 수신」(LogisticsResultAccess)의 Apex 클래스 접근으로 준다
 * ======================================================================================*/
@RestResource(urlMapping='/v1/supply-restriction-results')
global with sharing class LogisticsResultRestResource {
  /**
   * @description : 반영 결과 회신을 받아 처리 결과(200 · 400 · 404 · 409 · 500)를 응답한다.
   * @author      : 이은석(Kai) | 2026.10.18
   **/
  @HttpPost
  global static void receiveResult() {
    LogisticsResultService.ReceiveResult result;
    // DESC: 예기치 못한 예외는 되돌리고 500으로 답한다 — 기록이 반쯤 남지 않게 하고, 플랫폼 기본 오류 응답
    //       (예외 클래스 · 줄 번호 포함)을 외부에 내보내지 않는다. 상세는 디버그 로그에만 남긴다
    Savepoint beforeReceive = Database.setSavepoint();
    try {
      result = LogisticsResultService.receive(readBody(RestContext.request));
    } catch (Exception e) {
      Database.rollback(beforeReceive);
      System.debug(
        LoggingLevel.ERROR,
        'IF-004 수신 처리 실패: ' +
          e.getTypeName() +
          ' ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );
      result = LogisticsResultService.serverError();
    }
    // DESC: 본문을 직접 직렬화해 응답 형식({result, logNo} 또는 {error})을 고정한다
    RestResponse res = RestContext.response;
    res.statusCode = result.statusCode;
    res.addHeader('Content-Type', 'application/json');
    res.responseBody = Blob.valueOf(result.toJson());
  }

  // NOTE: UTF-8이 아닌 본문은 toString()이 StringException을 던진다 — 보낸 쪽 문제라 빈 본문으로 넘겨 400이 되게 한다
  private static String readBody(RestRequest req) {
    try {
      return req.requestBody == null ? null : req.requestBody.toString();
    } catch (StringException e) {
      return null;
    }
  }
}
