/* ======================================================================================
 * @description : IF-004 회신 콜아웃 테스트용 가짜 응답 — 요청 형식도 함께 검증하고 나간 요청을 모은다
 * @testTarget  : SupplyRestrictionResultService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 상태코드 · 본문 주입, 연결 실패(시간 초과 · 권한) 흉내, 요청 검증(Step 7-B)
 * ======================================================================================
 *  @note        : Apex 테스트에서는 실제 콜아웃이 금지된다. Test.setMock으로 이 객체를 주입하면 Http.send가 respond()를 부른다.
 *                 Mock은 External Credential 주체 접근을 검사하지 않는다 — 권한 없음은 연결 실패 메시지로 흉내 낸다
 * ======================================================================================*/
@IsTest
public class SupplyRestrictionResultMock implements HttpCalloutMock {
  private Integer statusCode;
  private String body;
  private String calloutError;

  // DESC: 테스트가 실제로 나간 요청 본문을 다시 꺼내 Assert할 수 있게 모은다 (job이 여러 번 돌아도 누적)
  public List<String> requestBodies = new List<String>();

  public SupplyRestrictionResultMock(Integer statusCode, String body) {
    this.statusCode = statusCode;
    this.body = body;
  }

  /** 응답 없이 CalloutException으로 끝나는 Mock (시간 초과 · 주체 접근 없음 흉내) */
  public static SupplyRestrictionResultMock failing(String message) {
    SupplyRestrictionResultMock mock = new SupplyRestrictionResultMock(
      null,
      null
    );
    mock.calloutError = message;
    return mock;
  }

  public HttpResponse respond(HttpRequest req) {
    // DESC: 응답만 돌려주면 요청이 틀려도 테스트가 통과한다 → 응답 전에 요청부터 검증한다
    Assert.areEqual(
      SupplyRestrictionResultService.ENDPOINT,
      req.getEndpoint(),
      'Named Credential(callout:HankkiInspection)의 IF-004 경로로 호출해야 한다'
    );
    Assert.areEqual('POST', req.getMethod(), '회신은 POST여야 한다');
    Assert.areEqual(
      'application/json',
      req.getHeader('Content-Type'),
      '본문은 JSON'
    );
    requestBodies.add(req.getBody());

    if (calloutError != null) {
      throw new CalloutException(calloutError);
    }
    HttpResponse res = new HttpResponse();
    res.setStatusCode(statusCode);
    res.setHeader('Content-Type', 'application/json');
    if (body != null) {
      res.setBody(body);
    }
    return res;
  }

  /** 마지막 요청 본문(JSON)을 Map으로 */
  public Map<String, Object> lastPayload() {
    return (Map<String, Object>) JSON.deserializeUntyped(
      requestBodies[requestBodies.size() - 1]
    );
  }
}
