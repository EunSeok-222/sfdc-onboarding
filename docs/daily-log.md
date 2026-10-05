# Daily Log

온보딩 기간(2026.10.01 ~ 10.19) 동안 날마다 배운 개념, 결정 사항, 남은 의문을 기록한다.

---

## D2 · 2026.10.02 ~ 10.05 (연휴 포함)

> 범위: 과제 이해 → 프로필·테스트 사용자 → Role 계층 → OWD·Public Group·공유 규칙 → Login As 검증 → 권한 매트릭스 → ERD 뼈대
> 산출물: `CLAUDE.md`(네이밍 보충 규칙), `docs/권한-매트릭스.md`(V1.1), `docs/ERD.md`(V0.1, 표는 비어 있음)
> 미완: 커스텀 오브젝트 5종 · 권한 집합 · Queue · Lightning App · 요건 정의서 회사 양식 반영

### 배운 개념 5개

1. **권한은 두 관문이다 — Profile/Permission Set은 "무엇을", OWD → Role → Sharing Rule은 "어느 레코드까지"**
   프로필은 사용자당 1개 필수이고 라이선스에 묶인다. 권한 집합은 0~N개이며 **더하기만** 된다(빼기 불가).
   OWD는 잠그는 쪽, Role 계층과 공유 규칙은 넓히는 쪽이다. 공유 규칙으로 접근을 좁힐 수는 없다.
   시스템 관리자는 두 관문을 모두 통과하므로 권한 설계를 검증할 수 없다 → 테스트 사용자가 필요한 이유.

2. **Role 계층은 읽기와 쓰기를 함께 상속하고, 위에서 아래로만 동작한다**
   커스텀 오브젝트는 OWD에서 `Grant Access Using Hierarchies`를 끌 수 있고(표준 오브젝트는 강제), 끄면 상속이 멈춘다.
   Role 트리 루트 `윈드밀소프트`는 Role이 아니라 org 이름이다. `This role reports to`가 org면 그게 최상위다.
   `Role Name` = `DeveloperName` = API Name. Label이 한글이면 자동 생성되지 않아 직접 입력한다.

3. **공유 규칙은 접근 수준을 `Read Only`로 지정할 수 있고, 대상은 Role 또는 Group만 가능하다**
   `Roles`는 그 Role 사용자의 소유분만, `Roles and Internal Subordinates`는 하위 Role 소유분까지 공유한다.
   Role 없는 소유자(`Process Automated`)의 레코드는 공유되지 않는다 → 최 대표에게 18건 중 17건만 보인 이유.
   Contact OWD가 `Controlled by Parent`면 공유 규칙 화면에 Contact Access 행 자체가 사라진다.
   계층 상속으로 생긴 접근은 `AccountShare`에 행으로 남지 않는다(Owner·Rule만 남음) → 데이터가 아니라 Login As로 확인한다.

4. **라이선스가 쓸 수 있는 프로필을 정한다**
   DE org의 Salesforce 라이선스는 잔여 1개라 테스트 사용자 3명은 Salesforce Platform(잔여 3개)으로 만들었다.
   표준 `Read Only` 프로필은 Salesforce 라이선스 전용이라 `Standard Platform User`를 복제해 쓰기 권한을 빼서 조회전용을 만들었다.
   Platform 라이선스는 Opportunity·Case·Campaign에 접근할 수 없다. 사용자는 삭제가 안 되고 비활성화해야 라이선스가 반납된다.

5. **레코드 보안은 Login As + URL 직접 접근으로 검증하고, 권한 매트릭스는 표로 펼쳐야 구멍이 보인다**
   목록에 안 보이는 것은 "숨김"과 "권한 없음"을 구분하지 못한다. 타인 소유 레코드 URL을 직접 입력해 거부되는 것이 증거다.
   목록 뷰 기본값 `최근 본 항목`은 0건이라 권한 문제로 오해하기 쉽다 → `모든 계정`으로 바꿔서 본다.
   Setup 화면에서 하나씩 설정할 때 안 보이던 과다 권한 2건(조회전용 Contact 쓰기, SV·팀장 Account·Contact 생성·삭제)이 매트릭스를 쓰면서 드러났다.

### 결정 사항

| #   | 결정                                                                                                                                                                             | 이유                                                                                                              |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| 1   | 테스트 사용자 3명(김 길동 SV · 박 팀장 권역팀장 · 최 대표 조회전용)은 Salesforce Platform 라이선스                                                                               | Salesforce 라이선스 잔여 1개. 업무가 Account + 커스텀 오브젝트만 쓰므로 제약 없음                                 |
| 2   | 데이터 모델은 Account + 커스텀 오브젝트로만 구성 (Opportunity·Case 사용 안 함)                                                                                                   | Platform 라이선스 접근 범위                                                                                       |
| 3   | 사용자·프로필·Role·OWD·공유 규칙은 Setup UI에서 직접 설정하고, 결과는 SOQL로 검증                                                                                                | 어드민 영역을 손으로 익히는 것이 D2의 목적. 설정 결과는 `ObjectPermissions`·`AccountShare`·`UserRole` 조회로 대조 |
| 4   | 테스트 사용자 3명의 UI 언어는 Korean                                                                                                                                             | Login As 시연이 가상 고객사처럼 보임. 디버깅이 불편해지면 English로 전환 가능                                     |
| 5   | Role 계층: 영업관리팀장(Kai) > 권역팀장 수도권·영남 > SV 수도권·영남. 영남은 빈 자리로 생성                                                                                      | 권역 간 비공개 구조를 보여주기 위함. Kai 본인도 최상위 Role에 배정 — 계층 밖 소유자의 레코드는 공유되지 않으므로  |
| 6   | 조회전용(최 대표)은 Role 없음. 공유 규칙 `ExecutiveReadAllAccounts` + Public Group `ExecutiveViewers`로 Read Only 열람                                                           | 계층에 넣으면 쓰기 권한까지 상속. Group이면 감사·CFO 추가 시 멤버만 추가                                          |
| 7   | 공유 범위는 `Roles and Internal Subordinates: 영업관리팀장`                                                                                                                      | `Roles`만 고르면 Kai 소유분만 공유되어 SV·팀장 소유 가맹점이 빠짐                                                 |
| 8   | Account OWD `Private`, Contact `Controlled by Parent` 유지. 커스텀 오브젝트도 Private + Grant Access Using Hierarchies 유지 예정                                                 | SV 간 비공개, 팀장은 SV 점검을 봐야 함                                                                            |
| 9   | Account·Contact 권한: SV·권역팀장 `R E`, 조회전용 `R`. 생성·삭제는 영업관리팀장(본사)만                                                                                          | 가맹점 등록·해지는 본사 업무. 가맹점이 M-D 부모가 되면 삭제 시 점검 이력 연쇄 삭제 위험                           |
| 10  | 점검표 관리 권한은 프로필이 아니라 권한 집합 `InspectionTemplateManagement`                                                                                                      | 직군이 아니라 담당. 기존 프로필 위에 얹는다                                                                       |
| 11  | 네이밍은 회사 Naming Convention v3.0 유지(접두사 없음, Label 한글 / API PascalCase). v3.0에 없는 Role·Profile·Permission Set·Queue·Public Group은 `CLAUDE.md` 보충 규칙으로 정함 | 신규 프로젝트라 구규칙(`_tr`·`_ts`)을 따를 이유가 없음. 한결기계 산출물 3종은 **문서 양식 참고용**으로만 사용     |
| 12  | 시연 데이터는 가상 브랜드 `한끼정성` 가맹점 4건, 소유자를 김 길동 2 · 박 팀장 1 · Kai 1로 분산                                                                                   | 실제 브랜드명 사용 금지. 소유자가 달라야 계층 상하 방향을 모두 시연 가능                                          |
| 13  | ERD는 Kai가 Mermaid로 직접 그리고 리뷰만 받는다. Schema Builder는 오브젝트 생성 후 검증·캡처용                                                                                   | 커리큘럼 가이드 4단계. Schema Builder는 기존 것만 그리고 드래그 생성은 Undo가 없음                                |
| 14  | 2차 범위: 가맹점주 포털(External 공유), Apex Managed Sharing, SV 재배치 소유권 일괄 이전 도구                                                                                    | 선언적 공유만으로 요구사항 충족. 포털은 별도 프로젝트 규모                                                        |

### 남은 의문

- [ ] **ERD 관계 유형 미결정**: 점검 ↔ 가맹점(Lookup/M-D), 템플릿 ↔ 결과항목(참조/복사), 시정조치는 점검 vs 결과항목, 페널티는 가맹점 vs 점검.
      시정조치·페널티를 M-D로 하면 OWD가 `Controlled by Parent`가 되는데 권한 매트릭스의 "Private 예정"과 충돌하지 않는가?
- [ ] **M-D 자식의 권한**: 점검 결과 항목은 소유자가 없다. SV가 결과 항목을 입력하려면 부모 점검에 Edit이 있으면 되는가, 아니면 오브젝트 권한 `C`도 필요한가? Login As로 검증 필요.
- [ ] **Queue 소유 레코드의 가시성**: `미배정 점검` Queue가 소유한 점검을 OWD Private에서 SV가 보려면 Queue 멤버십만으로 충분한가? "가져가기(Accept)" 흐름까지 Login As로 확인.
- [ ] **페널티 자동 생성의 실행 컨텍스트**: SV는 페널티 `R`뿐인데 재점검 결과로 페널티를 자동 생성하는 Flow/Apex는 System 모드로 돌려야 하는가? D3·D5에서 결정.
- [ ] **Enhanced Profile User Interface 전환 시점**: 지금은 한 장짜리 프로필 화면. 커스텀 오브젝트 5종이 생기면 설정량이 늘어 켜는 쪽이 유리할 듯 — 켜면 화면이 통째로 바뀜.
- [ ] **D1 문서 삭제 여부**: `docs/표준오브젝트-정리표.md`(추적 중, 삭제됨)와 `docs/발표-대본.md`(미추적, 사라짐)가 작업 트리에서 없어졌다. 의도한 정리인지 확인. 커밋 전에 결정 필요.
- [ ] **Git 정리**: 현재 브랜치 `chore/d1-env-setup`에서 D2 작업 중. `CLAUDE.md`·`docs/*` 미커밋, `.vscode/settings.json` 수정됨. D2용 브랜치를 새로 파고 D1 변경과 분리해 커밋.
- [ ] **Platform 라이선스의 D3 영향**: 리포트·대시보드·Flow 실행에 Platform 라이선스 제약이 있는지 D3 들어가기 전에 확인.
- [ ] **sf CLI `org login web` hang**: 이 PC에서 멈춰 `@salesforce/core` 스크립트로 우회 중. 공식 Windows 설치 프로그램 재설치로 해결되는지 미확인.
