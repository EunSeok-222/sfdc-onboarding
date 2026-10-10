# Daily Log

온보딩 기간(2026.10.01 ~ 10.19) 동안 날마다 배운 개념, 결정 사항, 남은 의문을 기록한다.

---

## D2 · 2026.10.02 ~ 10.05 (연휴 포함) — 요약

> 범위: 프로필·테스트 사용자 → Role 계층 → OWD·Public Group·공유 규칙 → Login As 검증 → 권한 매트릭스 → ERD → 데이터 모델·보안 메타데이터
> 산출물: `CLAUDE.md`(네이밍 보충 규칙), `docs/권한-매트릭스.md`, `docs/ERD.md`(V0.3), 커스텀 오브젝트 5종 · Role · 공유 규칙 · Queue · 권한 집합 (브랜치 `feat/d2-data-model-security`)

### 배운 개념

1. **권한은 두 관문**: Profile/Permission Set은 "무엇을", OWD → Role → 공유 규칙은 "어느 레코드까지". OWD는 잠그고 나머지는 넓히기만 한다. 관리자로는 검증할 수 없어 테스트 사용자가 필요하다.
2. **Role 계층**은 읽기·쓰기를 함께, 위에서 아래로만 상속한다. 커스텀 오브젝트는 `Grant Access Using Hierarchies`를 끌 수 있다.
3. **공유 규칙**은 Role 또는 Group 대상이고 `Read Only`로 줄 수 있다. Role 없는 소유자(Queue·`Process Automated`)의 레코드는 소유자 기반 공유에서 빠진다.
4. **라이선스가 프로필을 정한다**: Platform 라이선스는 Opportunity·Case·Campaign 불가, 표준 `Read Only` 프로필도 못 쓴다. 사용자는 삭제 불가, 비활성화로만 라이선스 반납.
5. **검증은 Login As + 타인 레코드 URL 직접 접근**으로 한다. 계층 상속은 `AccountShare`에 남지 않는다. 권한을 표(매트릭스)로 펼쳐야 과다 권한이 보인다.

### 결정 사항

- **사용자·라이선스**: 테스트 사용자 3명(김 길동 SV · 박 팀장 권역팀장 · 최 대표 조회전용)은 Platform 라이선스, UI 언어 Korean. 그래서 데이터 모델은 Account + 커스텀 오브젝트만 쓴다.
- **Role·공유**: 영업관리팀장(Kai) > 권역팀장 수도권·영남 > SV 수도권·영남. 최 대표는 Role 없이 Public Group `ExecutiveViewers` + 공유 규칙(`Roles and Internal Subordinates: 영업관리팀장`)으로 읽기 전용 열람. 계층에 넣으면 쓰기까지 상속되기 때문.
- **OWD·권한**: Account·점검·페널티 Private + 계층 상속 유지. 가맹점 생성·삭제는 본사(영업관리팀장)만. 점검표 관리는 프로필이 아니라 권한 집합 `InspectionTemplateManagement`.
- **ERD**: 점검 → 가맹점은 Lookup(점검마다 담당 SV 소유자가 필요), 결과 항목 → 점검과 시정조치 → 결과 항목은 Master-Detail(Roll-Up · 권한 상속), 결과 항목은 템플릿 값을 스냅샷 복사. Kai가 Mermaid로 직접 그리고 리뷰만 받았다.
- **네이밍·범위**: 회사 Naming Convention v3.0 + `CLAUDE.md` 보충 규칙. 실제 브랜드명 금지(가상 `한끼정성`). 포털·Apex Managed Sharing·소유권 일괄 이전은 2차 범위.

### 해결된 의문

- [x] ERD 관계 유형 → 위 결정대로 확정 (`docs/ERD.md` V0.3)
- [x] D1 문서 정리 → 표준 오브젝트 정리표를 저장소 밖으로 이동 (`845cc12`)
- [x] Git 정리 → `feat/d2-data-model-security` 브랜치로 분리 커밋 · push

---

## D3 · 2026.10.06 ~ 10.07

> 범위: Flow 2종 → 페널티 승인 · Email Alert → Data Loader 이관 · Duplicate Rule → Field History → 리포트 · 대시보드(역할별 확인)
> 산출물: Flow 2개, Approval Process 1개, Email Alert + 템플릿, 리포트 2개 · 동적 대시보드 1개, 이관 CSV 5개(`data/d3-migration/`), Duplicate Rule 1개, Field History 2개, D3 핵심 개념 흐름도
> 미완: org에서 만든 D3 메타데이터 레포 retrieve · 커밋, Login As 역할별 대시보드 캡처, Audit Trail · 보안 설정 점검 기록

### 결정 사항

| #   | 결정                                                                                                                                                          | 이유                                                                                                                             |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| 1   | 시정조치 기한 · 재방문 여부는 **Before-Save Flow** (위생 3일 · 그 외 7일, `BLANKVALUE`로 SV 입력값 유지)                                                      | 시정조치 자신의 필드만 채우므로 DML 없는 Before가 가장 빠름. 판정처럼 예외 · 테스트가 필요한 계산은 D4 Apex로 넘김               |
| 2   | 페널티는 **Approval Process**로 권역팀장 결재. 승인자 = 소유자의 Manager 필드, 승인 시 잠금 유지 · 반려 시 해제, Email Alert 1개를 양쪽에서 재사용            | 결재와 잠금이 필요한 규칙. Manager 필드 지정이라 SV 재배치에도 프로세스 수정 불필요. 확정된 페널티는 바뀌지 않아야 함            |
| 3   | 배정은 Assignment Rule 대신 **미배정 점검 Queue**                                                                                                             | Assignment Rule은 Lead · Case 전용이고 Platform 라이선스는 Case 불가. 대가: Queue 소유 레코드는 계층 · 소유자 기반 공유에서 빠짐 |
| 4   | 대시보드는 **대시보드 뷰어(동적)**, 리포트는 `Show Me = 모든 점검`. 리포트 · 대시보드 폴더를 각각 권역팀장 Role(하위 포함) · 경영진 그룹에 공유               | 지정 사용자로 두면 SV가 다른 SV의 점검 건수까지 보는 데이터 노출                                                                 |
| 5   | 이관은 매장코드 · 점검번호 **External ID upsert**, 부모 → 자식 5파일. 사업자번호 Duplicate Rule(Block) + Batch size 30. Field History는 점검 상태 · 항목 점수 | 재실행해도 중복 없음. 같은 배치 행끼리는 중복 비교가 안 되어 배치를 나눠 검증. 상태 전이와 점수 사후 수정을 추적할 필드가 핵심   |

### 남은 의문

- [x] **D3 메타데이터 레포 미반영** → 10/11 retrieve · 커밋 (PR #3). Quick Action · Field Update 2개 · 목록 뷰 · 레이아웃 변경도 함께 반영
- [ ] **자동 생성 API Name 정리**: Flow `UniqueName`, Duplicate Rule `DuplicateRule_20261006081519`, 대시보드 `BaeVYGbZQOtTTqDISQfvtgNpCrnVlZ`. Flow는 API Name 변경 불가라 새로 저장 후 기존 비활성화.
- [ ] **역할별 대시보드 확인**: 대시보드 폴더 공유 후 김 길동 25 · 박 팀장 26 · 최 대표 52(예상)가 나오는지 Login As로 캡처. Platform 라이선스로 리포트 · 대시보드 열람이 되는지도 같이 확인 (D2에서 이월).
- [ ] **페널티 자동 생성의 실행 컨텍스트** (D2에서 이월): BR-08 자동화를 After-Save Flow로 할지 Apex(`without sharing` 분리)로 할지 D4~D5에서 결정.
- [ ] **M-D 자식의 권한** (D2에서 이월): SV가 결과 항목을 입력하려면 부모 점검 Edit만으로 되는지, 오브젝트 권한 `C`도 필요한지 Login As 검증.
- [ ] **Queue 소유 점검의 가시성** (D2에서 이월): SV가 Queue 멤버십만으로 미배정 점검을 보고 가져갈 수 있는지 확인.
- [x] **Enhanced Profile User Interface 전환** (D2에서 이월) → 10/6 13:17에 이미 켜져 있음 (Setup Audit Trail로 확인)
- [ ] **sf CLI `org login web` hang** (D2에서 이월): `@salesforce/core` 스크립트로 우회 중. 재설치로 해결되는지 미확인.

## D4 · 2026.10.08

> 범위: Apex 문법 · sharing · SOQL(관계 · 집계) · DML · Governor Limit → InspectionService 작성 → Anonymous Apex 실행 → Debug Log LIMIT_USAGE로 벌크 안전 검증
> 산출물: `InspectionService.cls`(메서드 2개), SOQL 10문제 답안 · 실행 캡처, LIMIT_USAGE 캡처 2종(53건 · 253건), 벌크 테스트 데이터 1,000건(점검 200 · 결과 항목 800, `BULK-` 접두사)
> 미완: org의 `InspectionService` 레포 retrieve · 커밋, `countInspectionsByFranchise` 실행 검증, 루프 내 SOQL/DML 0건 코드 점검 캡처, `BULK-` 데이터 정리

### 결정 사항

| #   | 결정                                                                                                                 | 이유                                                                                                                                          |
| --- | -------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `InspectionService`를 **`with sharing`**으로 작성. 공유를 넘어야 하는 작업은 별도 클래스로 분리                      | 화면 · 트리거 · Batch 어디서 불려도 호출자의 공유 범위를 지킴. 선언을 생략하면 호출 맥락에 따라 동작이 달라져 예측 불가                       |
| 2   | 모든 메서드가 **`Set<Id>`를 받는 모양**. 단건 오버로드를 두지 않음                                                   | D5 트리거 · D6 Batch · D7 LWC가 같은 메서드를 재사용. 1건이든 200건이든 SOQL · DML 횟수가 변하지 않아야 함                                    |
| 3   | `judgeInspections`는 결과 항목을 조회하지 않고 **Roll-Up 필드만** 읽음. 호출자가 넘긴 레코드를 믿지 않고 Id로 재조회 | 결과 항목을 M-D로 묶어 총점 · 배점 · 필수 미흡 수를 부모에 올린 ERD 결정 덕분에 SOQL 1회로 끝남. DML 직후 메모리의 Roll-Up 값은 갱신되지 않음 |
| 4   | 가맹점별 점검 건수는 **Apex 집계**(`GROUP BY Franchise__c`). Map을 0으로 미리 채운 뒤 집계 결과로 덮어씀             | 가맹점–점검이 Lookup이라 Roll-Up Summary 불가(ERD R2의 대가). GROUP BY는 행이 없는 가맹점을 아예 반환하지 않아 `.get()`이 null                |
| 5   | 판정 기준 0.8 / 0.6을 **코드 상수**(`PASS_RATE` · `CORRECTION_RATE`)로 유지, D6에 Custom Metadata 이관 예정          | 오늘은 벌크 안전 검증이 목표. 본사가 기준을 바꿀 때마다 배포가 필요하므로 운영자가 Setup에서 바꿀 수 있어야 함                                |

### 검증

| 항목           | 53건 (판정 대상 45) | 253건 (판정 대상 245) |
| -------------- | ------------------- | --------------------- |
| SOQL queries   | 2 / 100             | **2 / 100**           |
| DML statements | 1 / 150             | **1 / 150**           |
| Query rows     | 90                  | 490                   |
| DML rows       | 45                  | 245                   |

판정 대상 5.4배에도 SOQL · DML 횟수 고정. 테스트 데이터 생성도 1,000건을 DML 2번(부모 insert → Id 수령 → 자식 insert)으로 처리.

### 남은 의문

- [ ] **BR-02의 60% 미만 처리**: 현재 코드는 `시정 필요` 미만을 모두 `불합격`으로 보냄. 요건 정의서 BR-02와 대조해 확정 필요.
- [x] **D4 메타데이터 레포 미반영** → 10/11 `InspectionService` retrieve, 헤더를 회사 형식으로 바꿔 커밋
- [ ] **`countInspectionsByFranchise` 실행 미검증**: 작성만 하고 Anonymous Apex로 돌려보지 않음. 8번 SOQL 결과(3회 가맹점 4곳)와 대조 예정.
- [ ] **`BULK-` 테스트 데이터 정리 시점**: 점검 200 · 결과 항목 800건이 org에 남아 판정 분포 · 리포트 수치를 왜곡함. 발표 캡처 재현 필요성 때문에 보류 중. M-D cascade라 점검만 지우면 됨.
- [ ] **페널티 자동 생성의 실행 컨텍스트** (D2 → D3 이월): BR-08을 After-Save Flow로 할지 Apex(`without sharing` 분리)로 할지. D5 트리거 설계에서 결정.
- [ ] **M-D 자식의 권한** (D2 → D3 이월): SV가 결과 항목을 입력하려면 부모 점검 Edit만으로 되는지, 오브젝트 권한 `C`도 필요한지 Login As 검증.
- [ ] **Queue 소유 점검의 가시성** (D2 → D3 이월): SV가 Queue 멤버십만으로 미배정 점검을 보고 가져갈 수 있는지 확인.
- [ ] **역할별 대시보드 확인** (D2 → D3 이월): 김 길동 25 · 박 팀장 26 · 최 대표 52가 나오는지 Login As로 캡처. `BULK-` 데이터가 수치를 흔드니 정리 후 또는 제외 조건으로 확인.
- [ ] **자동 생성 API Name 정리** (D3 이월)
- [x] **Enhanced Profile User Interface 전환** (D3 이월) → 이미 켜져 있음
- [ ] **sf CLI `org login web` hang** (D3 이월)
