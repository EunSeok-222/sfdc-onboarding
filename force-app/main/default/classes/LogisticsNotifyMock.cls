/* ======================================================================================
 * @description : 물류 통보 콜아웃 테스트용 가짜 응답 — 요청 형식도 함께 검증한다
 * @testTarget  : LogisticsNotifyService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 — 상태코드 · 본문 주입, 시간 초과 흉내, 요청 검증
 * ======================================================================================
 *  @note        : Apex 테스트에서는 실제 콜아웃이 금지된다. Test.setMock으로 이 객체를 주입하면 Http.send가 respond()를 부른다
 * ======================================================================================*/
@IsTest
public class LogisticsNotifyMock implements HttpCalloutMock {
  private Integer statusCode;
  private String body;
  private Boolean throwsTimeout = false;

  // DESC: 테스트가 실제로 나간 요청(헤더 · 본문)을 다시 꺼내 Assert할 수 있게 마지막 요청을 보관한다
  public HttpRequest lastRequest;

  public LogisticsNotifyMock(Integer statusCode, String body) {
    this.statusCode = statusCode;
    this.body = body;
  }

  /** 응답 없이 시간 초과로 끝나는 Mock */
  public static LogisticsNotifyMock timingOut() {
    LogisticsNotifyMock mock = new LogisticsNotifyMock(null, null);
    mock.throwsTimeout = true;
    return mock;
  }

  public HttpResponse respond(HttpRequest req) {
    // DESC: 응답만 돌려주면 요청이 틀려도 테스트가 통과한다 → 응답 전에 요청부터 검증한다
    Assert.isTrue(
      req.getEndpoint().startsWith('callout:HankkiLogistics'),
      'Named Credential(callout:HankkiLogistics)로 호출해야 한다. 실제: ' +
      req.getEndpoint()
    );
    Assert.isTrue(
      String.isNotBlank(
        req.getHeader(LogisticsNotifyService.HEADER_CORRELATION_ID)
      ),
      '재시도 중복을 막는 멱등성 키(X-Correlation-Id)가 있어야 한다'
    );
    Assert.areEqual('POST', req.getMethod(), '통보는 POST여야 한다');
    lastRequest = req;

    if (throwsTimeout) {
      throw new CalloutException('Read timed out');
    }
    HttpResponse res = new HttpResponse();
    res.setStatusCode(statusCode);
    res.setHeader('Content-Type', 'application/json');
    if (body != null) {
      res.setBody(body);
    }
    return res;
  }
}
