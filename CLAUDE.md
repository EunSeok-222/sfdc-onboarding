# sfdc-onboarding — 프로젝트 기준

윈드밀소프트 Salesforce 개발자 온보딩(2026.10.01 ~ 10.19) 개인 프로젝트. 10/19 15:00 팀장 발표.

**주제**: 가상 고객사 ㈜한끼정성(한식 프랜차이즈 본사)의 가맹점 정기점검 → 시정조치 → 재점검 → 페널티 관리

**데이터 모델**: Account(가맹점) + 커스텀 오브젝트 5종
`Inspection__c` 점검 · `InspectionResult__c` 점검 결과 · `CorrectiveAction__c` 시정조치 · `Penalty__c` 페널티 · `InspectionTemplateItem__c` 점검표 항목
필드 API Name은 추측하지 말고 `force-app/main/default/objects/` 메타데이터를 읽는다.

## 현재 단계

- D9 (10/15): 배포/형상관리 · 통합 · 산출물 · 리허설
- 설계 근거와 Day별 과제는 아래 「문서 위치」의 문서를 따른다. 진행 상황은 `docs/daily-log.md`가 최신이다.

## org 제약

- 대상 org: alias `kai-dev` (Developer Edition, API 67.0)
- **Salesforce 라이선스 잔여 1개**, **Salesforce Platform 라이선스 잔여 0개** (테스트 사용자 3명이 3개 모두 사용)
- 테스트 사용자 3명(김 길동 SV · 박 팀장 권역팀장 · 최 대표 조회전용)은 Platform 라이선스라
  **Lead · Opportunity · Case · Campaign · Product · Forecast 등 CRM 표준 오브젝트에 접근할 수 없다.**
  데이터 모델은 Account · Contact + 커스텀 오브젝트로만 구성한다. 이 제약을 벗어나는 설계를 제안하지 않는다.
- 사용자를 잘못 만들어도 삭제할 수 없다. 비활성화해야 라이선스가 반납된다.
- 이미 배포된 메타데이터의 API Name은 바꾸자고 제안하지 않는다(참조·배포 영향).

## 코드 규칙

전역 기준(`~/.claude/standards/`)과 겹치는 항목은 전역이 우선한다. 여기는 이 프로젝트에서 반드시 지킬 것만 적는다.

- Apex 클래스는 `with sharing` 기본. 예외가 필요하면 주석으로 이유를 남긴다.
- 루프 안 SOQL · DML 금지. 트리거는 200건 벌크를 기준으로 작성한다.
- 컬렉션 변수는 복수형 또는 `<값>By<키>` (예: `accountsById`, `inspectionsByFranchiseId`).
- 테스트: `Assert` 필수 · 실패 케이스 · 벌크(200건) 케이스 포함, org 전체 커버리지 85% 이상 유지.
  테스트 데이터는 `TestDataFactory`로 만든다. `SeeAllData=true`를 쓰지 않는다.
- 새 파일에는 v3.0 「소스 주석」 형식 헤더(`@description` · `@layer` · `@author` 등), 수정 시 이력 한 줄.
  라인 주석은 `DESC / TODO / WARN / NOTE / FIX / PERF`. 작성자 이은석(Kai).
- 기준값(합격선 · 시정선 · 기한 · 횟수)은 코드에 하드코딩하지 않고 `InspectionRule__mdt`를 `InspectionRuleSelector`로 읽는다.
- LWC에서 부르는 Apex: 읽기는 `@AuraEnabled(cacheable=true)`, DML이 있으면 `cacheable` 없이. 동적 SOQL의 정렬 컬럼은 화이트리스트로 검증한다.

## 아키텍처 (D4~D6에 정한 것 — 바꾸지 않는다)

- 오브젝트당 트리거 1개. 트리거는 `<개체명>TriggerHandler`로 위임만 하고, 핸들러는 분기만 하며, 로직은 `<개체명>Service`에 둔다.
- Batch · Scheduler · Controller도 로직을 갖지 않고 Service를 호출한다.
- 상태 전이 검증은 트리거(이전 값 `oldMap` 비교가 필요). 단일 레코드 필드 검증은 Validation Rule.
- 대량 · 주기 처리는 Batch + Schedulable. 건수가 적고 순서가 중요한 후속 작업만 Queueable.
- 화면: 레코드 1건 CRUD는 LDS(`lightning-record-form` 등)로 Apex 없이. 검색 · 집계 · 다중 오브젝트만 Apex Controller.

## 산출물 현황 — D8(10/14) 기준, `force-app/main/default` 파일 목록과 대조함

| 구분       | 이름                                                                                                                                                 | 역할                                                                                           |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| 트리거     | `Inspection.trigger` → `InspectionTriggerHandler`                                                                                                    | 상태 전이 검증 · 판정 세팅 · 가맹점 최근 점검일 갱신                                           |
| Service    | `InspectionService`                                                                                                                                  | 판정 계산(`applyJudgements`). `judgeInspections` · `countInspectionsByFranchise`는 호출자 없음 |
| Service    | `FranchiseInspectionDateService`                                                                                                                     | 가맹점 최근 정기점검일 재계산. 갱신 한 줄만 `update as system`(D8, SV FLS 실패 수정)           |
| Service    | `CorrectiveActionService`                                                                                                                            | 기한 초과 → 지연(`markOverdue`)                                                                |
| Service    | `LogisticsNotifyService` + `LogisticsNotifyMock`                                                                                                     | 공급 제한 승인 → 물류팀 통보 콜아웃 스텁(BR-08). 트리거 · Queueable에는 아직 연결 안 함        |
| Selector   | `InspectionRuleSelector`                                                                                                                             | `InspectionRule__mdt` 접근 (`passRate` · `correctionRate` · 기한)                              |
| Batch      | `OverdueCorrectiveActionBatch` + `OverdueCorrectiveActionScheduler`                                                                                  | BR-05, 매일 01:00                                                                              |
| Controller | `InspectionListController`                                                                                                                           | 내 점검 목록 검색 · 정렬(컬럼 화이트리스트) · 페이징(`search`)                                 |
| Controller | `CorrectiveActionController`                                                                                                                         | 점검의 시정조치 목록(`getByInspection`) · 미흡 결과 항목(`getDeficientResults`)                |
| Controller | `FranchiseHistoryController`                                                                                                                         | 매장 이력(SC-03) — 점검 · 시정조치 · 페널티 최근 12개월(`getHistory`)                          |
| LWC        | `inspectionList` 「내 점검 목록」                                                                                                                    | 점검 목록 datatable (D7)                                                                       |
| LWC        | `inspectionDetail` 「점검 상세」 · `inspectionJudgementPanel` 「점검 판정 패널」                                                                     | 점검 레코드 페이지. 상세에 시정조치 목록 + 추가 폼, 저장 후 `refreshApex`(D8)                  |
| LWC        | `correctiveActionForm` 「시정조치 추가」(비노출)                                                                                                     | `inspectionDetail` 안에서만 사용. 저장 성공 → `created` 이벤트                                 |
| LWC        | `franchiseHistoryTimeline` 「매장 이력」                                                                                                             | Account 레코드 페이지 「매장 이력」 탭                                                         |
| LWC        | `ldsUtils`(비노출)                                                                                                                                   | `reduceErrors` — 오류 객체를 문구 배열로                                                       |
| 페이지     | `Record_Page1` 「점검 Record Page」 · `Account_Record_Page`                                                                                          | 점검: Org Default(Desktop) · Account: App Default(가맹점 점검 앱 · Desktop)                    |
| 연동       | Named Credential · External Credential `HankkiLogistics`                                                                                             | 물류 시스템 주소(`.example` 임의 주소) · 인증 헤더. 비밀값은 레포에 없음                       |
| 권한 집합  | 「점검 목록 조회」 `InspectionListAccess`                                                                                                            | 컨트롤러 3개 호출 권한 (Description 226 / 255자)                                               |
| 권한 집합  | 「점검표 관리」 `InspectionTemplateManagement`                                                                                                       | 점검표 항목 Modify All                                                                         |
| 권한 집합  | 「물류 연동」 `LogisticsIntegrationAccess`                                                                                                           | External Credential `HankkiLogistics` 주체 접근                                                |
| 테스트     | `*Test` 9개, `TestDataFactory`                                                                                                                       | 63건 통과 · Org 94% · 프로젝트 클래스 92.4% (D8, 10/14 23:42 RunLocalTests)                    |
| 설정       | `InspectionRule__mdt` 「점검 기준」 `Default` 레코드                                                                                                 | 합격 0.8 · 시정 0.6 · 기한 3/7일 · 재점검 3회                                                  |
| 클릭       | Validation Rule(재점검이면 원본 필수), Flow `UniqueName` 「기한·재방문 세팅」, Screen Flow `CorrectiveAction_Complete_Screen` 「시정조치 완료 등록」 | D5                                                                                             |
| 잔재       | `OnboardingService`                                                                                                                                  | D1 연습 코드. 업무와 무관 — 정리 여부는 D9 결정                                                |

## 네이밍 보충 규칙

전역 기준(`~/.claude/standards/naming.md`)에 **없는 항목만** 여기서 정한다.
전역 기준에 있는 항목(개체/필드, Flow, Approval Process, Apex, LWC/Aura/VF, Custom Label)은 그대로 따른다.

| 대상           | Label (화면)             | API Name                                          | 예                                             |
| -------------- | ------------------------ | ------------------------------------------------- | ---------------------------------------------- |
| Role           | 한글 Natural Text        | PascalCase `<직무><구분>`                         | `영업관리팀장` / `SalesAdminManager`           |
| Profile        | 한글 `<업무영역> <역할>` | (API Name 없음)                                   | `가맹점점검 SV`                                |
| Permission Set | 한글 Natural Text        | PascalCase `<대상>Management` 또는 `<기능>Access` | `점검표 관리` / `InspectionTemplateManagement` |
| Queue          | 한글 Natural Text        | PascalCase                                        | `미배정 점검` / `UnassignedInspection`         |
| Public Group   | 한글 Natural Text        | PascalCase                                        | `경영진 열람` / `ExecutiveViewers`             |

**근거**: 권한 매트릭스 V1.2(산출물 폴더)에 이미 정해진 명명을 따른다. 그 명명은 `naming.md`의 「일반 원칙」(의미가 명확한 풀네임)과
Approval Process API Name 패턴(`Quote_DiscountApproval` — PascalCase 영문)에서 유추한 것이다.
회사 기준 v3.0에 해당 항목이 추가되면 그것을 우선한다.

### 자동 생성 API Name — 이름 유지 예외

화면(Lightning App Builder · Flow Builder)에서 한글 Label로 만들면서 생긴 이름이다. 이미 배포 · 참조 중이라 바꾸지 않고 Label로 구분한다.
새로 만들 때는 API Name을 직접 입력해 이런 이름이 생기지 않게 한다.

| API Name       | 유형                    | Label                  | 용도 · 참조                                         |
| -------------- | ----------------------- | ---------------------- | --------------------------------------------------- |
| `UniqueName`   | Flow (Before Save)      | 기한·재방문 세팅       | `CorrectiveAction__c` 생성 시 기한 세팅 (D5)        |
| `Tab`          | CustomTab               | 내 점검                | `FranchiseInspectionApp` 탭 → 페이지 `FlexiPage`    |
| `FlexiPage`    | FlexiPage (App Page)    | 내 점검                | 탭 `Tab`                                            |
| `Record_Page1` | FlexiPage (Record Page) | 점검 Record Page       | `Inspection__c` View 재정의 (Org Default · Desktop) |
| `UtilityBar`   | FlexiPage (Utility Bar) | 가맹점 점검 UtilityBar | `FranchiseInspectionApp`의 유틸리티 바              |

## 오브젝트·필드 Label 언어

- **Label은 한글, API Name은 영문 PascalCase**(전역 기준 v3.0대로 밑줄 제거)로 만든다.
  예) Label `점검` / API `Inspection__c`
- 가상 고객사(프랜차이즈 본사) 시연이 목적이라 화면은 한글이어야 자연스럽다.

## 문서 위치

- 산출물 · 설계 근거: `C:\Users\dldms\OneDrive\文档\산출물` — 레포 밖에서 관리한다. 레포에 사본을 두지 않는다.
  요건 정의서(01) · ERD(02) · 권한 매트릭스(03) · 인터페이스 정의서(06) · 보안 점검 결과표 · 발표계획. 버전은 파일명에서 최신본을 확인한다.
- 학습 자료: `C:\Users\dldms\OneDrive\文档\핵심개념` — Day별 핵심개념 HTML과 커리큘럼(`SFDC_개발자_온보딩_커리큘럼_참여자용.html`).
  레포에 두지 않는다. Day 문서의 「오늘 할 일」 탭이 그날의 작업 순서다.
- 레포 `docs/`: 진행 기록 `daily-log.md`(매일 17:00 갱신. 없으면 진행 상황을 추측하지 말고 묻는다) · `decision-log.md` ·
  Day별 설계 · 인수인계 md · `d8-security-review.md`

## 형상관리

- 작업 브랜치: `develop` 하나 (10/15부터). 이전 Day 브랜치(`chore/d1-…` ~ `feat/d4-…`)는 그대로 둔다.
- push · PR · 원격 브랜치 정리는 Kai가 요청할 때만 한다.

## 배포 · org 안전 규칙 (10/16 kai-dev 오배포 이후)

- `logistics/`는 hankki-logistics 전용 패키지다. kai-dev 배포 명령에 logistics 경로나 컴포넌트 이름을 넣지 않는다.
- 이 레포와 두 org(kai-dev · hankki-logistics)는 Claude Code 세션 하나에서만 작업한다.
- 모든 sf 명령에 `-o <alias>`를 명시한다. 기본 org에 기대지 않는다.
- 경로 · 매니페스트 없는 `sf project deploy start`는 쓰지 않는다(packageDirectories 전체가 대상이 될 수 있다).
  배포 전에 대상 org와 컴포넌트 목록을 먼저 보여 준다.

## 자주 쓰는 명령어

```bash
sf project deploy start --source-dir force-app/main/default/lwc/<name> -o kai-dev   # LWC 하나
sf project deploy start --metadata ApexClass:<Name> -o kai-dev                       # Apex 하나
sf apex run test --class-names <Name>Test --synchronous --result-format human -o kai-dev
sf apex run test --test-level RunLocalTests --code-coverage --result-format human -o kai-dev
sf lightning generate component --name <camelName> --type lwc --output-dir force-app/main/default/lwc
sf org open -o kai-dev
sf project deploy start --source-dir logistics/main/default/classes/<Name>.cls -o hankki-logistics   # 물류 org Apex 하나
sf apex run test --class-names <Name>Test --synchronous --result-format human -o hankki-logistics  # 물류 org 테스트
```

배포는 파일 단위로 한다(폴더 전체보다 에러 찾기 쉬움). 테스트는 배포 직후 해당 클래스만 먼저, 전체는 하루 끝에.
**폴더 전체(`--source-dir force-app`) 배포 금지** — 점검 검색 레이아웃이 아직 레포에 없다.
