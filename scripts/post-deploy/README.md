# 배포 후 수작업 체크리스트

레포 배포만으로 끝나지 않는 설정이다. 대상 org마다 위에서부터 순서대로 하고, 마지막에 **관리자가 아닌 실행 사용자로 스모크 1회**를 한다.
비밀값(Client ID · Secret)과 Username은 레포 · 문서 · 캡처에 남기지 않는다.

## kai-dev

1. **ECA · Principal (Kai 직접 — 비밀값)**

   | 구분                      | 이름                                                                         | 하는 일                                                                                                                                                           |
   | ------------------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | ECA (IF-004 수신용)       | 「물류 결과 회신」 `LogisticsResultClient`                                   | 생성 — Client Credentials, Run As 「물류 연동 처리」, 허용 권한 집합 「물류 결과 수신」. 발급된 Consumer Key · Secret은 물류 org IF-004 송신용 Principal에 넣는다 |
   | Principal (IF-001 송신용) | External Credential `HankkiLogisticsOAuth` → `HankkiLogisticsOAuthPrincipal` | 물류 org IF-001 수신용 ECA의 Client ID · Secret 입력                                                                                                              |

   ECA는 정책에 Run As Username이 들어가 레포에 두지 않는다(retrieve 금지).

2. **이벤트 트리거 실행 사용자** — `deploy-logistics-subscriber-config.ps1 -TargetOrg kai-dev` 실행 →
   구독 Suspend → **Resume from Tip** → `scripts/apex/logisticsNotifyWakeUp.apex` → Setup → Apex Jobs에서
   `LogisticsNotifyQueueable`의 Submitted By가 「물류 연동 처리」인지 확인(Process Automated면 미적용).
3. **권한 집합 할당**
   | 권한 집합                                         | 대상                       | 비고                                                                   |
   | ------------------------------------------------- | -------------------------- | ---------------------------------------------------------------------- |
   | 「물류 연동」 `LogisticsIntegrationAccess`        | 물류 연동 처리             | Principal 접근 + **User External Credential Read**(콜아웃 사용자 필수) |
   | 「물류 결과 수신」 `LogisticsResultAccess`        | 물류 연동 처리             | IF-004 수신 API                                                        |
   | 「물류 통보 요청」 `LogisticsNotifyRequestAccess` | 공급 제한 승인자(권역팀장) | 없으면 승인 시 이벤트 발행 실패가 로그에 남는다                        |
   | 「인터페이스 로그 조회」 `PenaltyLogisticsAccess` | SV · 권역팀장 · 관리자     | 없으면 로그 소유자가 되지 못한다(규칙 B)                               |
4. **사용자 Manager** — 승인 단계 「상위 관리자 승인」은 페널티 소유자의 Manager로 간다.
   - SV의 Manager = 권역팀장 (SV 소유 페널티 → 권역팀장 승인)
   - 권역팀장의 Manager = 영업관리팀장 (공급 제한 승인 경로 — 권역팀장 소유 페널티 → 영업관리팀장 승인)
5. **점검표** — `scripts/apex/inspectionTemplateReplace.apex` 1회(20항목 · 100점 · 위생 필수 6, 다시 실행해도 같은 결과).
6. **스모크** — 권역팀장 계정으로 공급 제한 페널티 승인 → 인터페이스 로그 IF-001 「성공」 · 접수번호 확인(전송은 물류 연동 처리).

## hankki-logistics

1. **배포 범위** — `--source-dir logistics/main/default`에는 Named Credential `HankkiInspection` · External Credential `HankkiInspectionOAuth`가
   들어 있다. 재배포 시 Principal에 입력한 인증 정보가 유지되는지 확인하지 않았으므로 **NC/EC를 빼고 컴포넌트를 지정해** 배포한다.
2. **ECA · Principal (Kai 직접 — 비밀값)**
   | 구분                      | 이름                                                                           | 하는 일                                                                                                                                           |
   | ------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
   | ECA (IF-001 수신용)       | 출고 제한 수신 API용 ECA                                                       | 생성 — Client Credentials, Run As 물류 연동 사용자(「출고 제한 수신」 보유). 발급된 Client ID · Secret은 kai-dev IF-001 송신용 Principal에 넣는다 |
   | Principal (IF-004 송신용) | External Credential `HankkiInspectionOAuth` → `HankkiInspectionOAuthPrincipal` | kai-dev ECA 「물류 결과 회신」의 Consumer Key · Secret 입력                                                                                       |
3. **권한 집합 할당**
   | 권한 집합                                        | 대상                      | 비고                                                                                                |
   | ------------------------------------------------ | ------------------------- | --------------------------------------------------------------------------------------------------- |
   | 「출고 제한 수신」 `SupplyRestrictionApiAccess`  | 물류 연동 사용자          | IF-001 수신 API(Salesforce Integration 라이선스)                                                    |
   | 「출고 제한 관리」 `SupplyRestrictionManagement` | 물류 담당                 | 처리 상태 변경 · 회신 오류 읽기                                                                     |
   | 「점검 회신」 `InspectionCallbackAccess`         | 처리 상태를 바꾸는 사용자 | Principal 접근 + **User External Credential Read**. 없으면 회신이 「전송실패 · 연결 실패」로 남는다 |
4. **스모크** — 「점검 회신」을 가진 물류 담당 계정으로 출고 제한을 반영완료로 저장 → 회신 상태 「전송완료」 · kai-dev 수신 로그(IF-004) 확인.
   물류 담당 계정이 없으면 빈 본문 인증 확인 호출(kai-dev가 400으로 거절, 기록 없음)로 인증 경로만 먼저 확인한다.
