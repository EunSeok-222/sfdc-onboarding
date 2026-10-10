# sfdc-onboarding — 프로젝트 기준

윈드밀소프트 Salesforce 개발자 온보딩(2026.10.01 ~ 10.19) 개인 프로젝트.

**주제**: 한식 프랜차이즈 본사의 가맹점 정기점검 → 시정조치 → 재점검 → 페널티 관리

## org 제약

- 대상 org: alias `kai-dev` (Developer Edition, API 67.0)
- **Salesforce 라이선스 잔여 1개**, **Salesforce Platform 라이선스 잔여 0개** (테스트 사용자 3명이 3개 모두 사용)
- 테스트 사용자 3명은 Platform 라이선스라 **Opportunity · Case · Campaign에 접근할 수 없다.**
  데이터 모델은 Account + 커스텀 오브젝트로만 구성한다.
- 사용자를 잘못 만들어도 삭제할 수 없다. 비활성화해야 라이선스가 반납된다.

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

**근거**: `naming.md`의 「일반 원칙」(의미가 명확한 풀네임을 사용한다)과,
가장 성격이 가까운 Approval Process API Name 패턴(`Quote_DiscountApproval` — PascalCase 영문)을 유추해 적용했다.
회사 기준 v3.0에 해당 항목이 추가되면 그것을 우선한다.

## 오브젝트·필드 Label 언어

- **Label은 한글, API Name은 영문 PascalCase**(전역 기준 v3.0대로 밑줄 제거)로 만든다.
  예) Label `점검` / API `Inspection__c`
- 가상 고객사(프랜차이즈 본사) 시연이 목적이라 화면은 한글이어야 자연스럽다.
