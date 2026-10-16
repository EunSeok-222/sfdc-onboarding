/* ======================================================================================
 * @description : Salesforce 아웃바운드 프록시가 DNS 실패를 HTTP 503 응답으로 바꿔 돌려주는 것을
 *                실측으로 확인하는 스크립트. 상태코드만으로는 "상대 시스템 장애"와
 *                "우리 쪽 주소 설정 오류"를 구분할 수 없다는 근거 자료다
 * @layer       : Script
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 (D8 심화 요건 ① 실측 근거)
 * ======================================================================================
 *  실행 : sf apex run --file scripts/apex/checkCalloutResponse.apex --target-org kai-dev
 *  NOTE : 레코드를 조회하지도 저장하지도 않는다. 콜아웃 응답만 본다
 *  NOTE : 발표 시연에서 재실행 가능해야 한다. 주소가 .example 예약 도메인이라 결과는 항상 같다
 * ======================================================================================*/

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:HankkiLogistics/v1/supply-restrictions');
req.setMethod('POST');
req.setHeader('Content-Type', 'application/json');
// NOTE: 멱등성 키. 실제 통보가 아니므로 check- 접두사로 구분한다
req.setHeader('X-Correlation-Id', 'check-' + Datetime.now().getTime());
// NOTE: 기본 10초. 명시하지 않으면 플랫폼 기본값에 의존한다
req.setTimeout(10000);
req.setBody('{"storeCode":"CHECK-0000","startDate":"2026-10-15","endDate":"2026-10-21","reason":"connectivity check"}');

HttpResponse res = new Http().send(req);

// DESC: 503을 누가 보냈는지가 핵심이다. Server와 X-Squid-Error가 프록시의 지문이다
System.debug(LoggingLevel.ERROR, '>>> status        = ' + res.getStatusCode() + ' ' + res.getStatus());
System.debug(LoggingLevel.ERROR, '>>> Server        = ' + res.getHeader('Server'));
System.debug(LoggingLevel.ERROR, '>>> X-Squid-Error = ' + res.getHeader('X-Squid-Error'));
System.debug(LoggingLevel.ERROR, '>>> body          = ' + res.getBody().left(300).replaceAll('\\s+', ' '));
