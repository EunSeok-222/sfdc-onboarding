/* ======================================================================================
 * @description : OnboardingService 동작을 검증하는 테스트 클래스
 * @testTarget  : OnboardingService
 * @layer       : Test
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.01   Kai        Created     최초 작성
 * ======================================================================================*/
@IsTest
private class OnboardingServiceTest {
  @IsTest
  static void getGreetingWithName() {
    Test.startTest();
    String greeting = OnboardingService.getGreeting(' Kai ');
    Test.stopTest();
    Assert.areEqual('Hello, Kai!', greeting, '이름 앞뒤 공백을 제거해야 한다');
  }

  @IsTest
  static void getGreetingWithBlankName() {
    Test.startTest();
    String greeting = OnboardingService.getGreeting(null);
    Test.stopTest();
    Assert.areEqual(
      'Hello, Salesforce!',
      greeting,
      '이름이 없으면 기본값을 사용해야 한다'
    );
  }
}
