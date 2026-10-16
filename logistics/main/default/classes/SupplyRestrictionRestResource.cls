/* ======================================================================================
 * @description : 출고 제한 통보 수신 Apex REST 진입점 (IF-001, POST /services/apexrest/v1/supply-restrictions)
 * @testClass   : SupplyRestrictionRestResourceTest
 * @layer       : RestResource
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.16   Kai        Created     최초 작성 — 요청을 SupplyRestrictionService에 넘기고 결과를 HTTP 응답으로 옮김
 * ======================================================================================
 *  @see         : SupplyRestrictionService.cls, 인터페이스 정의서 V1.1 IF-001
 *  @note        : 진입점은 HTTP 입출력만 다룬다. 검증 · 저장 로직은 Service에 둔다
 * ======================================================================================*/
@RestResource(urlMapping='/v1/supply-restrictions')
global with sharing class SupplyRestrictionRestResource {
  /**
   * @description : 출고 제한 통보를 받아 접수 결과(201 · 200 · 400)를 응답한다.
   * @author      : 이은석(Kai) | 2026.10.16
   **/
  @HttpPost
  global static void receive() {
    RestRequest req = RestContext.request;
    SupplyRestrictionService.ReceiveResult result = SupplyRestrictionService.receive(
      headerValue(req, SupplyRestrictionService.HEADER_CORRELATION_ID),
      req.requestBody == null ? null : req.requestBody.toString()
    );
    // DESC: 본문을 직접 직렬화해 응답 형식({requestNo, status} 또는 {error})을 정의서대로 고정한다
    RestResponse res = RestContext.response;
    res.statusCode = result.statusCode;
    res.addHeader('Content-Type', 'application/json');
    res.responseBody = Blob.valueOf(result.toJson());
  }

  // NOTE: HTTP 헤더 이름은 대소문자를 구분하지 않지만 Apex Map 키는 구분한다 — 송신 측 표기가 달라도 찾게 한다
  private static String headerValue(RestRequest req, String name) {
    for (String key : req.headers.keySet()) {
      if (key.equalsIgnoreCase(name)) {
        return req.headers.get(key);
      }
    }
    return null;
  }
}
