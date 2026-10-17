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

- [x] **BR-02의 60% 미만 처리** → 요건 정의서 BR-02 "60점 미만 불합격"과 일치. 현재 코드 유지 (D5에서 확인)
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

---

## D5 · 2026.10.11 (커리큘럼 10/8분)

> 범위: Flow vs Apex 재정리 → 트리거 대상 규칙 확정 → 설계 리뷰 → 핸들러 패턴 구현 → 1 · 200 · 400건 벌크 검증 → 테스트 초안
> 산출물: `Inspection.trigger`, `InspectionTriggerHandler`, `FranchiseInspectionDateService`, `InspectionTriggerHandlerTest`(6개), Account `LastRegularInspectionDate__c`(최근 정기점검일), 백필 · 벌크 검증 · 시연 스크립트(`scripts/apex/`)
> 미완: 요건 정의서 흐름도 수정(페널티 레인 분리), `InspectionService` 커버리지 35%, 역할별 대시보드 캡처

### 결정 사항

| #   | 결정                                                                                                                                              | 이유                                                                                                                                                      |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | 트리거 규칙 3개: **상태 전이 검증 · 판정 세팅 · 최근 정기점검일**. 시정조치 기한은 **Flow 유지**. 페널티 자동 생성(BR-07 · 08)은 D6 이후          | 기한은 같은 레코드 필드만 채우는 단순 계산. 나머지는 허용 표 · 예외 규칙 · 삭제/복원 재계산이 필요. BR-08은 과거 점검을 거슬러 비교해야 해 D5 범위를 넘음 |
| 2   | 점검 상태는 **6개**(점검예정 · 점검완료 · 시정중 · 지연 · 재점검완료 · 종료). '페널티승인대기'는 점검 상태에서 제외                               | 흐름도상 페널티는 "시정과 별도로" 진행 → 상태 필드 하나로 동시 표현 불가. 페널티 진행은 페널티의 유형 · 승인 상태가 담당                                  |
| 3   | 판정은 **'점검완료'로 바뀔 때 + 점검완료 상태에서 점수(Roll-Up)가 바뀔 때**만 계산. 시정중 이후는 고정. before update에서 `Trigger.new` 직접 수정 | 결과 항목을 하나씩 저장할 때 중간 판정이 찍히는 것을 막음. `applyJudgements`로 메모리 계산만 분리해 SOQL · DML 0                                          |
| 4   | 집계는 점검 건수 대신 **최근 정기점검일**(정기점검, 점검예정 제외). 남은 점검으로 `MAX` 재조회, 대상 가맹점을 null로 미리 채움                    | BR-01 "월 1회 정기점검" 누락 매장을 바로 찾는 값. +1/-1 누적은 한 번 어긋나면 계속 틀림. 가맹점 변경 시 이전 · 새 가맹점 둘 다 재계산                     |
| 5   | 날짜 재계산만 **`without sharing` 분리 클래스**. 핸들러 · 서비스는 `with sharing`                                                                 | SV 재배치 후 이전 SV가 과거 점검을 삭제하면 편집 권한 없는 가맹점을 갱신해야 함. 공유를 넘는 범위를 한 클래스로 좁힘                                      |
| 6   | 재귀 방지 static 플래그를 쓰지 않고 **`oldMap` 비교**로 바뀐 것만 처리. `before insert` 제외                                                      | 실제 재귀 경로가 없음(before는 DML 없음, Account 트리거 없음). 플래그는 같은 트랜잭션의 정당한 재실행을 건너뛸 위험. insert 검증은 이관 데이터를 막음     |

### 검증

| 경로                        | 1건   | 200건     | 400건                 |
| --------------------------- | ----- | --------- | --------------------- |
| 날짜 경로 SOQL / 트리거 DML | 1 / 1 | **1 / 1** | **2 / 2** (200 × 2회) |
| 판정 경로 SOQL / 트리거 DML | 0 / 0 | **0 / 0** | -                     |

- 테스트 6개 통과: 트리거 · 핸들러 100%, `FranchiseInspectionDateService` 94%, `InspectionService` 35%
- 백필: 가맹점 48곳 SOQL 2 · DML 1, 27곳 값 채움. 빈 21곳 = 샘플 거래처 14 + 완료된 정기점검 없는 매장 7

### 남은 의문

- [ ] **요건 정의서 흐름도 수정**: '페널티승인대기'를 점검 흐름에서 빼고 페널티 레인(유형 · 승인 상태)으로 분리. 선택 목록 값은 문서 수정 후 비활성화
- [ ] **페널티 승인자가 요건과 다름**: BR-07 ~ 09는 유형별로 권역팀장 · 영업관리팀장 · 영업본부장 승인인데, 현재 승인 프로세스는 Manager 1단계뿐. 영업본부장 Role도 없음
- [ ] **Duplicate Rule과 날짜 재계산 충돌 위험**: 가맹점 Duplicate Rule이 수정 시 Block이라, 사업자번호 중복 가맹점이 생기면 Account update가 막혀 점검 저장까지 실패. 현재 중복 0건
- [ ] **`InspectionService` 커버리지 35%**: `judgeInspections` · `countInspectionsByFranchise` 테스트 없음 (D6)
- [ ] **페널티 자동 생성의 실행 컨텍스트** (D2 → D4 이월): BR-08 구현 시 결정. 날짜 재계산과 같은 `without sharing` 분리 패턴이 후보
- [ ] **sf CLI `--json`이 큰 로그에서 멈춤**: 400건 실행 로그(약 8.9MB)에서 `Maximum call stack size exceeded`. org 실행은 정상. 큰 로그는 `--json` 없이 실행
- [ ] **이월**: `countInspectionsByFranchise` 실행 검증, `BULK-` 데이터 정리, M-D 자식 권한, Queue 소유 점검 가시성, 역할별 대시보드 캡처, Flow `UniqueName` 정리, sf CLI `org login web` hang

## 10/12 (월) D6 — 테스트 · 비동기 Apex · 설정 데이터 | 결정과 이유

1. **판정 테스트는 DB를 타지 않기로 했다** — 경계값(80·79·60·59)마다 가맹점·점검·결과
   항목을 insert하면 SOQL·DML이 배로 늘어난다. 판정은 Roll-Up 세 값만 보는 순수 계산이고
   Roll-Up은 읽기 전용이라, `JSON.deserialize`로 값을 주입했다. 7개가 3~20ms에 끝난다.
2. **실패 케이스는 "막혔다"가 아니라 "이 이유로 막혔다"까지 검증하기로 했다** —
   저장 실패만 보면 다른 이유로 막혀도 통과한다. `Database.update(ins, false)`로 부분
   저장해 `SaveResult`를 받고, 오류 메시지와 `getFields()[0] == 'Status__c'`까지 Assert.
   예외를 던지는 `update ins;`는 테스트 자체를 죽이므로 쓰지 않았다.
3. **BR-05 지연 처리는 Batch + Schedulable로 갔다** — 기능이 아니라 "한 트랜잭션 한도를
   넘는가"로 골랐다. 가맹점이 늘면 쿼리 행 50,000을 반드시 넘고, execute마다 한도가
   리셋되는 청크 처리라야 건수에 비례해 안전하다. Queueable은 한 트랜잭션 안에서 끝나야
   해서 탈락(BR-08 페널티 생성이 거기에 맞다), @future는 원시 타입·체이닝 불가,
   Scheduled Flow는 단위 테스트로 보장하기 어려워 제외 — D5에서 정한 기준 그대로.
4. **배치는 호출만 하고 로직은 Service에 두기로 했다** —
   `execute(bc, scope) { CorrectiveActionService.markOverdue(scope); }`. D5에서 정한
   "트리거는 호출만, 로직은 핸들러·서비스" 원칙을 실행 방식만 바꿔 그대로 적용했다.
   덕분에 같은 로직을 배치·화면·테스트 어디서든 같은 입구로 부른다.
5. **기준값은 Custom Setting이 아니라 Custom Metadata로 뺐다** — Custom Setting은
   정의만 배포되고 데이터는 org마다 다시 입력해야 한다. 합격선·시정선은 개발 org에서
   운영 org로 값까지 따라가야 하는 업무 정책이라 `InspectionRule__mdt`가 맞다.
   비활성화 스위치는 org·사용자마다 달라야 하므로 Custom Setting(Hierarchy),
   화면 문구는 번역 대상이라 Custom Label로 나눴다.

### 겪은 것

- `Test.stopTest()`가 없으면 배치가 실행되지 않는다. **테스트는 통과하는데 커버리지가
  0%로 나와** 한참 헤맸다. 비동기는 stopTest 시점에 비로소 돌아간다.
- 상수를 메타데이터로 바꾸기 전/후에 `ApexTestResult`를 조회해 비교했다. 경계값 테스트
  7개가 양쪽 모두 Pass — 구조만 바뀌고 판정 결과는 그대로라는 증명. 테스트를 먼저 쓴
  이유가 이 장면이었다.

### 내일(D7)로 넘긴 것

- 과제인 화면 2개 설계 초안 완료(SC-02 상세 · SC-04 목록). 오전 발표 후 구현 착수.

## 10/13 (화) D7 — LWC 기초 · 데이터 연동 | 결정과 이유

1. **상세(SC-02)는 `lightning-record-form`(LDS)로, Apex 없이 갔다** — 레코드 1건 CRUD는
   캐시·동기화·FLS를 플랫폼이 준다. 판정 패널만 `@wire(getRecord)`: `recordId` 하나로
   조회가 정해지고, record-form과 LDS 캐시를 공유해 저장 직후 새로고침 없이 판정이 바뀐다.
2. **목록(SC-04)은 칩·검색·정렬·페이징을 imperative 한 경로로 통일했다** — 처음엔 칩만
   `@wire`로 생각했으나, 같은 Apex를 두 방식으로 부르면 늦게 온 응답이 화면을 덮어쓰고 조건
   객체도 둘로 갈라진다. 정렬·페이징은 서버(`ORDER BY` · `LIMIT/OFFSET`, OFFSET 최대 2,000은
   알고 선택). 같은 점검일은 `Name`으로 순서를 고정해 페이지 경계의 중복·누락을 막고,
   화면은 마지막 요청의 응답만 반영한다.
3. **칩은 LWC가 "칩 → 상태 목록"을 갖고, Apex는 `Status__c IN :statuses`만 한다** — 업무
   묶음이 바뀌어도 Apex는 그대로. 칩은 해야 할 점검(점검예정) · 시정 대기(시정중+지연) ·
   전체 3개. 「점검중」은 요건서 §3과 D5 전이표 어디에도 없는 값이라 뺐다(설계 초안 오류).
4. **권한은 관리자가 아니라 김 길동 계정으로 검증했다** — 판정(`Judgement__c`)의 레이아웃
   Read-Only + FLS 읽기 전용은 권한 매트릭스 V1.2대로 이미 걸려 있었고, 관리자에게 연필이
   보인 건 "Edit Read Only Fields" 권한 때문이었다. 반대로 새 Apex 클래스는 관리자만 실행할 수
   있어 김 길동 목록이 막혔다 → 권한 집합 「점검 목록 조회」(`InspectionListAccess`) 부여.
   조회가 `with sharing` + `USER_MODE`라 데이터 범위는 늘지 않는다(김 길동 27 · 박 팀장 28 ·
   최 대표 254건으로 확인).
5. **에러는 `reduceErrors({ body: event.detail })` + `ShowToastEvent`(sticky)로 올렸다** —
   record-form 에러에는 `body`가 없어 그대로 넘기면 일반 문구만 나온다. 실제 화면에서
   record-form 배너에는 일반 문구("An error occurred…"), Toast에는 D5 트리거 문구가 함께 떠서
   감싼 효과를 확인했다. 에러는 읽기 전에 사라지면 안 되므로 sticky, 성공은 dismissible.

## 10/14 (수) D8 — LWC 심화 · 보안 · 외부 연동 | 결정과 이유

> 만든 것: 점검 상세의 조치 추가(`correctiveActionForm` → `created` 이벤트 → 부모 `refreshApex`, `CorrectiveActionController`),
> 보안 점검 결과표(`docs/d8-security-review.md`, runAs 테스트 4건), 물류 통보 콜아웃 스텁(`LogisticsNotifyService` · Mock ·
> Named/External Credential `HankkiLogistics` · 권한 집합 「물류 연동」), 매장 이력 타임라인 SC-03(`FranchiseHistoryController` ·
> `franchiseHistoryTimeline`, Account 레코드 페이지 「매장 이력」 탭 · App Default 가맹점 점검 앱), 발표 계획 1p(`docs/demo/`)
> 테스트: RunLocalTests(23:42) 프로젝트 63건 Pass 100% · Org Wide 94% · 프로젝트 클래스 92.4%

1. **보안 필드 층은 기존 판정(`Judgement__c`) 편집 FLS + runAs 테스트 4건으로 증명했다** — 시연용
   「내부 메모」 필드는 요건서 · ERD · 권한 매트릭스 어디에도 없어 발표를 위해 요건을 만드는 셈이고,
   `with sharing`을 뺀 코드를 임시 배포해 "수정 전" 화면을 만드는 것도 org에 위험을 남겨 하지 않았다.
   대조군(같은 저장문을 관리자가 실행하면 성공)으로 막은 것이 코드가 아니라 SV의 필드 권한임을 보였다.
2. **최근 정기점검일 갱신 한 줄만 `update as system`으로 고쳤다** — 김 길동(SV)으로 재현하니 정기점검을
   점검완료로 저장할 때 FLS 때문에 실패했다. 관리자로만 돌던 테스트는 못 잡았다. 권한을 넘는 범위를
   그 한 줄로 좁히고, SV runAs 회귀 테스트를 붙였다. 컨트롤러는 D7에 이미 `with sharing` · `USER_MODE` ·
   정렬 화이트리스트가 있어 고치지 않았다 — 없던 것을 고친 것처럼 적지 않는다.
3. **심화 요건은 BR-08 「공급 제한 승인 즉시 물류팀 통보」 콜아웃 스텁으로 했다** — 요건서 As-Is의
   "통보 지연으로 제한 기간에 출고 발생"을 직접 푸는 연동이다(HACCP 연동은 요건 근거가 없어 제외).
   응답별로 재시도 여부를 나눴다(4xx 불가 · 429/5xx/시간 초과 가능, 멱등성 키 = 페널티 Id).
   승인 저장은 DML 트랜잭션 한가운데라 동기 콜아웃이 불가해, 호출부는 Queueable로 분리할 다음 단계로 남겼다.
4. **프록시 503(ERR_DNS_FAIL)은 코드를 바꾸지 않고 문서로 남기기로 했다** — 없는 주소로 호출하면
   CalloutException이 날 거라 가정했지만, 실측해 보니 Salesforce 프록시(squid)가 DNS 실패를 503으로 돌려줬다.
   상태코드만으로는 상대 장애와 우리 설정 오류를 구분할 수 없어, 503은 재시도로 두고
   "503 + X-Squid-Error면 우리 설정부터 확인"을 인터페이스 정의서에 적는다.
5. **10/19 발표는 현장 흐름(점검 → 판정 → 시정조치 → 매장 이력)을 중심으로 한다** — 구현과 테스트가
   가장 많이 쌓인 경로이고, 아직 못 푼 두 가지(SV 페널티 공유 경로, Queueable 연결)가 시연 한가운데
   오지 않는다. 다른 안(페널티 · 연동 중심, 매장 이력 중심)과 비교해 골랐다.

### 겪은 것

- 점검 검색 레이아웃이 레포에 없어, **폴더 전체를 배포할 때마다 org에서 다시 설정한 것이 지워졌다**(두 번).
  이후로는 작업한 파일만 배포한다.
- 매장 이력 페이지를 Org Default로 활성화했다가 App Default로 바꿨다. 활성화 정보가 레포에 있는
  앱 파일(`FranchiseInspectionApp`)에 들어가야 다음 배포 때 풀리지 않는다 — FlexiPage와 함께 retrieve했다.
- 테스트 출력의 "Tests Ran"은 `@TestSetup`을 포함한 숫자다. `LogisticsNotifyServiceTest`가 7로 보이지만 메서드는 6개다.
- `Assert.fail`을 try 안에 두면 `catch(Exception)`이 그 실패까지 삼켜 거짓 통과한다 — 결과를 변수로 받고 밖에서 검증했다.
- `lightning-record-form`(`layout-type="Full"`)은 페이지 레이아웃의 2단 배치를 따르지 않는다 → `columns="2"`.
- 김 길동(SV) 화면에서도 페널티가 관리자와 같은 건수로 보였다. 어떤 공유 경로인지는 아직 확인하지 않았다.

### 내일(D9)로 넘긴 것

- **커밋**: 10/14 13:39 이후 변경이 전부 미커밋. 기능 단위로 나눠 커밋한다.
  `docs/demo/Salesforce_온보딩_발표_D8_과제.html`은 레포에 넣지 않는다(삭제). `CLAUDE.md` 「현재 단계」 · 「산출물 현황」 갱신.
- **결정할 것**
  1. SV 페널티 공유 경로 — `Penalty__Share`의 RowCause(소유자 · 공유 규칙 · 수동)로 확인
  2. 페널티 승인 단계 — 요건 BR-07~09는 유형별 승인자 3명, 지금은 권역팀장(Manager) 1단계. 영업본부장 사용자 · Role 없음
  3. 페널티 자동 생성(BR-08 반복 지적 · 연속 불합격) — D5에 미룬 뒤 미구현. 구현할지, 범위 밖으로 문서화할지
  4. 물류 통보 호출부 — Queueable 연결 · 재시도 상한 · 시간 초과 판별(메시지 문구 의존)
  5. 매장 이력에 미래 일정 표시 — 세종점 · 의정부점 · 인천송도점에 10/15 점검예정
  6. 매장 이력 「(위생 3일)」 문구 — 시정조치 쿼리에 `InspectionResult__r.Category__c` 추가
  7. 레이아웃 버튼 정리 — Account의 New Case, 점검의 New Contact · New Opportunity (Platform 사용자는 쓸 수 없음)
  8. 점검 검색 레이아웃 retrieve — 폴더 전체 배포 때 org 설정이 지워지지 않게
  9. 코드 정리 — `InspectionService`의 호출자 없는 메서드 2개(커버리지 49% 원인), D1 잔재 `OnboardingService`
  10. 접근 모드 미지정 DML — 공식 문서로 기본 동작 확인 후 `InspectionService` · `CorrectiveActionService`에 `as system` 명시 여부
  11. Flow API Name `UniqueName`(시정조치 기한 자동설정) — 이름은 바꾸지 않고 산출물에 예외로 기록
  12. 권한 집합 「점검 목록 조회」 Description 226 / 255자 — 다음 추가 전에 정리
- **산출물**: 화면 설계(03 솔루션 기능 및 화면 설계서) · 단위 테스트 결과(07) · 배포 절차(11 Cut Over / 19 소스 이관 목록 — 양식 결정) ·
  인터페이스 정의서(06: IF-001 물류 통보 구현 · IF-002 알림톡 설계만 · IF-003 POS 2차) 작성. 요건서 · ERD(HTML)를 회사 양식으로 옮길지 결정
- **문서 정리**: 발표 계획 1p ⑤의 테스트 숫자(55건 · 93% → 63건 · 94%), `d8-security-review.md` 문서 정보 버전(V1.0 → V1.2),
  보안 점검 결과표 HTML(V1.3)을 레포에 둘지 · 문서 번호

## 10/15 (목) D9 — 인터페이스 설계 · 물류 실연동 계획 · 산출물 | 결정과 이유

> 10/16 소급 작성(Cowork 정리 · Kai 확인). D9는 설계 · 계획의 날이고, 구현은 D10으로 이어졌다.
> 만든 것: 인터페이스 정의서 06 V1.0 → V1.1(IF-001 실연동 · IF-002 알림톡 설계 · IF-003 POS 2차 · IF-004 회신 설계),
> 요건 정의서 V1.1, D9 핵심개념, 물류 연동 구현 계획(문서 폴더 `D9_물류연동_구현계획.md`), 모의 발표(14:30–16:30)

1. **인터페이스는 IF-001 구현 · IF-002 설계 · IF-003 2차에 IF-004(반영 결과 회신)를 더해 양방향으로 잡았다** — IF-001의 접수번호는
   「요청을 받았다」일 뿐이다. 요건서 As-Is 「통보 지연으로 제한 기간에 출고」를 닫으려면 실제 반영 여부를 돌려받아야 한다. 회신은 비동기.
2. **점주 알림톡은 3종(시정 요청 · 페널티 확정 · 시정 지연 매일 10:00), 수신 번호는 점주 휴대전화(Account 신규 필드)로 정했다** —
   요건서 V1.1 BR-12로 근거를 올리고, 1차는 정의서 설계만.
3. **요건서를 V1.1로 고쳤다** — §3 점검 상태 7 → 6개(페널티 레인 분리, D5 결정 2), §4 BR-12 추가, §5 1차 연동 정정(알림톡 스텁 → 물류 통보 IF-001).
4. **물류 시스템은 두 번째 org(hankki-logistics)로 만들고 OAuth 2.0 Client Credentials(External Client App)로 실제 통신한다** —
   Mock만으로는 인증 · 주소 · 권한 문제가 보이지 않는다. 새 Connected App은 만들 수 없어 External Client App. 소스는 같은 레포 `logistics/`.
5. **재처리는 최대 3회 · 1 → 5 → 30분으로 설계했다** — (변경: D10에 1 → 5 → 10분)
6. **브랜치는 develop 하나, 기준점 태그 `d9-before-logistics`, 최종 PR develop → main** — 개인 프로젝트라 기능 브랜치를 두지 않는다.
7. **배포 절차는 샌드박스 → 운영 기준, 양식은 11 Cut Over(본문) + 19 소스 이관 목록(부록). 테스트 결과는 07 단위** — 시나리오를 먼저 쓰고 결과는 최종 RunLocalTests 뒤.
8. **IF-004 수신 권한은 조건 기반 공유 규칙(공급 제한 → 공개 그룹)으로 열기로 했다** — (D10 정석 전환 뒤 재검토 대상)

### 겪은 것

- 모의 발표 피드백: 양방향 통신이 어떻게 작동하는지 · 인터페이스 리스트의 소스/타겟 · 샘플 데이터(JSON/XML) · **인터페이스 로그 필수** ·
  시스템 구조 · 배포 리스트 · 목적을 더 분명하게 · 가맹점 화면에서 바로 점검 생성 · 결과 항목 입력을 더 직관적으로 · 정기점검은 항목 자동 ·
  「필수」 기준이 무엇인지. → D10에 반영 범위를 정함

### 내일(D10)로 넘긴 것

- 물류 실연동 Step 0~8(계획서), 07 단위 테스트 시나리오, 06 정의서 갱신, 발표계획 갱신(구현 뒤)

## 10/16 (금) D10 — 물류 실연동(IF-001) · 승인 잠금 문제와 정석 연동 구조 전환 | 결정과 이유

> D9에서 못다 한 실연동을 이어서 했고, 그 과정에서 「승인된 페널티에 연동 결과를 어떻게 남기나」 문제가 생겨 구조를 바꿨다. (Cowork 정리 · Kai 확인)
> 만든 것: 물류 org 출고 제한 수신 API(`SupplyRestrictionRestResource` · `SupplyRestrictionService` · 「출고 제한 수신」 · 「출고 제한 관리」),
> 물류 org External Client App 「한끼정성 점검 연동」(Client Credentials · Run As 「물류 연동」), kai-dev External Credential `HankkiLogisticsOAuth` · Named Credential URL 교체,
> IF-001 실호출 스모크(201 · `SR-000000` → 재전송 200 · 같은 접수번호), kai-dev 연동 사용자(Alias `lgproc`, Salesforce Integration),
> 정석 구조(인터페이스 로그 `IntegrationLog__c` · `LogisticsNotifyEvent__e` · 이벤트 트리거 · 처리 Queueable · 깨우기 스크립트 · 실행 사용자 설정 틀),
> 07 단위 테스트 시나리오 V1.0(자동 70 · 연동 수동 5 · 수정 사항 7), 오답노트(문서 폴더 `D10_오답노트_승인잠금과_연동실행사용자.html`)
> 테스트: kai-dev 기준선(10:50, 오배포 정리 직후) RunLocalTests 78 실행(메서드 74 = 프로젝트 63 + 샘플 앱 11) · 실패 0 · Org Wide 94% /
> 물류 org 9건 통과(RestResource 100% · Service 94%) / 정석 구조 15건 중 14건(Service 96% · Queueable 84% · 트리거 · 핸들러 100%, Org 94%)

1. **잘못 배포된 kai-dev 컴포넌트는 삭제 매니페스트로 되돌리고, CLAUDE.md에 안전 규칙을 넣었다** — 다른 Claude Code 세션이 물류 org용
   오브젝트 · 클래스 3개 · 권한 집합을 kai-dev에도 배포했다. 레코드 · 할당 0건이라 dry-run 뒤 삭제(Deploy `0AfdL00000hOdFZSA0`).
   규칙: `logistics/`는 hankki-logistics 전용 · 세션 하나 · 모든 sf 명령에 `-o` · 경로 없는 deploy 금지.
2. **물류 org 수신 권한 집합은 Salesforce Integration 라이선스로 묶었다** — PSL(Salesforce API Integration)에 묶은 권한 집합은 Apex 클래스
   접근을 담을 수 없는데, 수신 API는 클래스 접근이 필요하다.
3. **SOQL · DML 접근 모드를 코드에 전부 명시했다** — Step 1 테스트가 「No such column」 · 필드 접근 불가로 실패. API 67.0은 SOQL · DML 기본이
   user mode다. 사용자 책임은 user mode, 시스템 책임(준비 데이터 · 결과 기록)만 `as system` + WARN, 테스트는 실제 연동 사용자 runAs.
4. **External Credential의 Scope는 비웠다** — 스모크 1회차(13:37) `invalid_request · scope parameter not supported`. Client Credentials의 범위는
   External Client App의 OAuth Scope로 정해진다. Scope를 비우고 Client ID를 다시 넣은 뒤 201.
5. **스모크용 `PEN-000001`의 기간은 저장으로 채웠다(10/17 ~ 10/23)** — 두 org 데이터를 맞추려고. 같은 상관 ID라 E2E에는 재사용하지 않는다.
6. **산출물은 6종 + 인터페이스 정의서만, 한결기계 양식이 있으면 따르고 없으면 자유양식** — 모의 발표 피드백 중 인터페이스 로그 ·
   양방향 동작은 구현으로 답한다. 연동 수동 확인은 07 양식의 「통합테스트」 시트에 넣어 09는 따로 만들지 않는다.
7. **승인 잠금 문제는 정석 구조(Outbox + 연동 전용 사용자)로 다시 설계했다** — 처음 설계는 「승인자 권한의 Queueable이 외부 호출 후
   잠긴 페널티에 결과 기록」이었다. 권역팀장 runAs 테스트에서 `Approval.unlock`이 `INSUFFICIENT_ACCESS_OR_READONLY`로 실패 — 비동기 Apex는
   큐에 넣은 사람 권한으로 돌고, 승인 잠금은 시스템 모드로도 우회되지 않는다. 권한 확대(Modify All) · 잠금 해제는 권한 매트릭스와 D3 결정
   (확정된 페널티 불변)에 어긋나 기각. 이제 승인 트랜잭션은 로그 「전송대기」만 쓰고 이벤트를 발행(커밋 후)하며, 외부 호출은 연동 사용자가
   이벤트 트리거 → Queueable로 한다. 승인된 페널티는 수정하지 않는다(페널티 물류 필드 4개는 역할이 없어져 삭제 대상).
8. **재처리는 최초 1회 + 재시도 3회, 1 → 5 → 10분으로 바꿨다** — 지연 Queueable의 지연 상한 안에서 끝내려고. 30분을 지키려면 스케줄러가 더 필요하다.
9. **로그 소유자는 페널티 소유자, 경영진은 로그 열람에서 뺐다** — 페널티를 보는 사람이 그 로그도 보게(BR-10). 연동 로그는 운영 기록.
10. **실행 사용자 설정(PlatformEventSubscriberConfig)은 Username을 비운 틀 + 배포 때 채우는 스크립트로 관리한다** — Username은 org마다 달라
    고정 파일은 운영 배포에 못 쓰고, 패키지 폴더 안에 두면 넓은 배포 · retrieve 때 사고가 난다. `scripts/post-deploy/`(Deploy `0AfdL00000hQrEPSA0`).
11. **Step 7(IF-004)은 시작하지 않고 설계만 발표한다** — 18:00 컷라인의 관문(16:30 · 17:00)을 지났다. 새 구조에서 IF-004는
    「수신 API가 같은 로그에 수신 행을 쓰는 것」으로 단순해졌다.

### 겪은 것

- **관리자로만 실행하면 권한 문제가 보이지 않았다** — 오전 스모크는 Kai(관리자)라 성공했고, 권역팀장 runAs에서야 잠금 해제 실패가 드러났다.
  D8(SV FLS)에 이어 같은 함정 → 오답노트로 정리.
- Apex 잠금 · 잠금 해제 설정이 꺼져 있었다(테스트 5건 `NoAccessException`) → 켰지만 권역팀장은 여전히 못 풀었다. 정석 전환 뒤에는 쓰지 않는다.
- External Client App의 Run As 칸에 계획서 설명 문구를 그대로 넣었다 → 실제 Username으로 고침.
- 스모크 2회차는 Claude Code가 실행해 Kai 화면에 남지 않았다. 같은 명령을 다시 돌려도 결과가 같다(멱등성).
- 참고 조회: 김 길동 Manager = 박 팀장, 페널티 소유자 = 김 길동 → 지금은 모든 페널티를 박 팀장이 승인. ERD V1.0 「소유자 = 발의 팀장」과 다르다.
- 점검표 템플릿이 D2 기능 확인용 샘플 4개(배점 40)뿐 — BR-02(위생 40 · 서비스 30 · 매뉴얼 30) · BR-03(위생 필수 6개)이 데이터에 없다.
  「미흡」 기준도 둘이다(이관 README 「배점의 60% 미만」 · TestDataFactory 「만점 미만」), 요건서에는 없다.
- 실제 승인 테스트를 위해 TestDataFactory의 가맹점 소유자를 SV로, 테스트 사용자에게 실제 역할 계층을 줬다(Mixed DML은 runAs로 분리).
  공용 메서드를 쓰는 5개 클래스 52건 재실행 통과.
- 실행 사용자 설정 스크립트: PowerShell 래퍼인 `sf`의 경고가 오류로 처리됨 → 종료 코드로 판단, 메타데이터 폴더 이름은 `PlatformEventSubscriberConfigs`.
- 로그 소유자를 페널티 소유자로 지정하자 `TRANSFER_REQUIRES_READ` — 로그 읽기 권한이 없는 사용자는 소유자가 될 수 없다.
  기록 기능 때문에 승인이 막히면 안 되므로 소유자 규칙을 다시 정한다.
- 10/19 발표 순서는 동료와 정해 진행자에게 통보했다.

### 내일(주말)로 넘긴 것

- **정석 구조 마무리**: 로그 소유자 규칙 결정 · 수정 → 15건 통과, Queueable 커버리지 85% 이상, 페널티 물류 필드 4개 삭제, 커밋
  → **완료(10/17)**: 로그 소유자 B안(읽기 권한 있으면 페널티 소유자, 없으면 기본 소유자) · 테스트 18건 전부 통과(Queueable 100% ·
  Service 96%) · 필드 4개 삭제 Deploy `0AfdL00000hQtUjSAK` · 박 팀장 「물류 연동」 해제(CLI) · 커밋 `1fce02a` `bc6eee2` `a628c07`
- **[화면]** Apex 잠금 · 잠금 해제 설정 끄기 — 박 팀장 「물류 연동」 할당 해제(완료 10/17 · CLI) · 최 대표 「인터페이스 로그 조회」 해제(완료)
- **Step 6 E2E**: 새 공급 제한 페널티(소유자 김 길동 · 기간 · `DEMO-`) → 박 팀장 승인 → 로그 전송대기 → 성공 ·
  **처리자 = 「물류 연동 처리」** 확인 → 물류 org 레코드 → 캡처
- **Step 8**: 두 org RunLocalTests(`--output-dir`), 07 결과 · 새 테스트 추가, 06 V1.2(Endpoint · 샘플 JSON · Scope · 재처리 · Outbox),
  ERD V1.1, 권한 매트릭스 V1.3, 배포 절차(11 + 19 · 배포 후 수작업), 화면 설계(03), 발표계획
- **결정할 것**
  1. 점검표를 BR-02 · 03대로 재구성 + 「필수는 위생만」 검증 규칙 + 미흡 기준 하나로(요건서 V1.2)
  2. 피드백 반영 범위: 정기점검 항목 자동 생성(BR-11) · 가맹점 「점검 생성」 버튼 · 결과 항목 입력 화면 · 상태 진행 바
  3. IF-004 구현 여부(주말 선택)
  4. 페널티 유형별 승인자(BR-07 ~ 09) — 2차로 문서화
  5. 커버리지 85% 미달: `InspectionService` 49% · `InspectionRuleSelector` 60%
