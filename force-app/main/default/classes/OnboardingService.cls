/* ======================================================================================
 * @description : 개발 환경 구축 확인용 서비스 (deploy 테스트)
 * @testClass   : OnboardingServiceTest
 * @layer       : Service
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.01   Kai        Created     최초 작성
 * ======================================================================================*/
public with sharing class OnboardingService {
  /**
   * @description : 이름을 받아 환영 메시지를 만든다.
   * @author      : 이은석(Kai) | 2026.10.01
   * @param name 사용자 이름 (비어 있으면 'Salesforce'로 대체)
   * @return String 환영 메시지
   **/
  public static String getGreeting(String name) {
    String targetName = String.isBlank(name) ? 'Salesforce' : name.trim();
    System.debug(LoggingLevel.INFO, 'getGreeting: ' + targetName);
    return 'Hello, ' + targetName + '!';
  }
}
