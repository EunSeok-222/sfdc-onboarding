// DESC: 물류 통보(IF-001) 대기 로그 처리를 다시 시작한다 — 「물류 통보 이벤트」만 발행하고 아무것도 보내지 않는다 (D10 Step 5R)
// 실행: sf apex run --file scripts/apex/logisticsNotifyWakeUp.apex -o kai-dev
// NOTE: 실제 전송은 이벤트 트리거의 실행 사용자(연동 사용자)가 한다 — 이 스크립트를 실행한 사람 권한으로 콜아웃하지 않는다.
//       커밋 후 발행이라 이 실행이 끝난 뒤 이벤트가 나간다
// NOTE: 처리 대상은 전송대기 · 재시도대기이고 다음 시도 시각이 지난 로그뿐이다. 중단 · 실패 로그를 다시 보내려면 상태를 먼저 바꿔야 한다
// NOTE: 실행자에게 이벤트 발행(「물류 통보 요청」 또는 관리자)과 로그 읽기(「인터페이스 로그 조회」) 권한이 필요하다.
//       익명 실행에서는 SYSTEM_MODE를 쓸 수 없어(컴파일 오류) 건수 조회는 USER_MODE로 한다
Set<String> dueStatuses = new Set<String>{
  LogisticsNotifyService.LOG_STATUS_PENDING,
  LogisticsNotifyService.LOG_STATUS_RETRY
};
Integer pendingCount = [
  SELECT COUNT()
  FROM IntegrationLog__c
  WHERE InterfaceId__c = :LogisticsNotifyService.INTERFACE_ID
    AND Status__c IN :dueStatuses
  WITH USER_MODE
];
Database.SaveResult result = EventBus.publish(
  new LogisticsNotifyEvent__e(InterfaceId__c = LogisticsNotifyService.INTERFACE_ID)
);
System.debug(
  LoggingLevel.ERROR,
  '>>> 깨우기 이벤트 ' + (result.isSuccess() ? '발행 예약(커밋 후)' : '발행 실패 ' + result.getErrors()) +
  ' · 처리 대기 로그 ' + pendingCount + '건'
);
