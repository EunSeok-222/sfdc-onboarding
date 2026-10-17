# D3 데이터 마이그레이션 — Data Loader 적재 파일

대상 org: `kai-dev` · 작성일: 2026.10.06 · 작성자: 이은석(Kai)

가맹점 30곳의 점검 이력(2026.04 ~ 10)을 Data Loader로 적재하기 위한 CSV다.
RecordTypeId·OwnerId·TemplateItem__c는 2026.10.06에 `kai-dev`에서 조회한 실제 Id다.
다른 org에 적재하려면 이 값을 다시 조회해 바꿔야 한다.

## 1. 적재 순서

| 순서 | 파일                          | 오브젝트            | Operation  | 매칭 키 (External ID) | 부모 참조 (External ID)                                                                    | 행 수   | 예상 실패                  |
| ---- | ----------------------------- | ------------------- | ---------- | --------------------- | ------------------------------------------------------------------------------------------ | ------- | -------------------------- |
| 1    | `01_accounts.csv`             | Account             | **Upsert** | `StoreCode__c`        | -                                                                                          | 32      | **2** (HK-0031, HK-0032) ※ |
| 2    | `02_inspections.csv`          | Inspection__c       | **Upsert** | `InspectionNo__c`     | `Franchise__r:Account-StoreCode__c`                                                        | 40      | 0                          |
| 3    | `03_reinspections.csv`        | Inspection__c       | **Upsert** | `InspectionNo__c`     | `Franchise__r:Account-StoreCode__c`, `OriginalInspection__r:Inspection__c-InspectionNo__c` | 8       | 0                          |
| 4    | `04_results.csv`              | InspectionResult__c | **Insert** | 없음                  | `Inspection__r:Inspection__c-InspectionNo__c`                                              | 144     | 0                          |
| 5    | `05_reinspection_results.csv` | InspectionResult__c | **Insert** | 없음                  | `Inspection__r:Inspection__c-InspectionNo__c`                                              | 32      | 0                          |
|      | **합계**                      |                     |            |                       |                                                                                            | **256** | **2**                      |

※ **HK-0031·HK-0032는 `BusinessRegNo__c` 중복 차단 테스트용이다.**
각각 HK-0006(명동점), HK-0019(울산삼산점)와 사업자번호만 같다.
필드는 Unique가 아니고, Duplicate Rule `가맹점_사업자번호_중복차단`(2026.10.06 생성, Active)이 차단한다.

| 항목                    | 설정                                                                       |
| ----------------------- | -------------------------------------------------------------------------- |
| Matching Rule           | `가맹점_사업자번호_일치` — `BusinessRegNo__c` EXACT, 빈 값은 비교하지 않음 |
| Action On Create / Edit | Block / Block                                                              |
| Record-Level Security   | Bypass sharing rules (볼 수 없는 매장과도 비교)                            |

**01은 Batch size를 30으로 바꿔서 적재한다** (Settings → Batch size, 적재 후 200으로 되돌림).
Duplicate Rule은 같은 배치 안의 레코드끼리는 비교하지 않고, 이미 저장된 레코드와만 비교한다.
기본값 200이면 32행이 한 배치로 같이 들어가 HK-0006과 HK-0031이 서로 비교되지 않아 **둘 다 생성된다**.
30으로 나누면 1~30행이 먼저 저장되고, 두 번째 배치(31~32행)가 저장된 원본과 비교되어 2건이 실패한다.

### 순서가 중요한 이유

- **02 → 03**: 재점검은 `OriginalInspection__r:Inspection__c-InspectionNo__c`로 02의 점검을 참조한다.
  02가 없으면 참조를 찾지 못해 실패한다. Validation Rule `ReinspectionRequiresOriginal`도 같이 걸린다.
- **02·03 → 04·05**: 결과 항목은 점검의 Master-Detail 자식이라 부모 점검이 먼저 있어야 한다.
- 03을 02와 한 파일로 합치지 않은 이유: 한 배치 안에서 아직 생성되지 않은 레코드를 External ID로 참조할 수 없다.

### Upsert / Insert를 나눈 기준

- **Upsert (01~03)**: External ID가 있다. 재실행해도 같은 키 레코드를 갱신만 하고 중복은 만들지 않는다.
- **Insert (04·05)**: 결과 항목에는 External ID가 없다. **두 번 실행하면 결과 항목이 중복 생성되고 Roll-Up 총점이 두 배가 된다.**
  재적재할 때는 먼저 해당 점검의 결과 항목을 삭제한다.
- Data Loader 버전에 따라 Insert 매핑 화면에서 External ID 참조 컬럼(`Inspection__r:Inspection__c-InspectionNo__c`)이 보이지 않을 수 있다(확인 필요).
  그때는 **Upsert + 매칭 키 `Id`**로 실행한다. Id 컬럼이 비어 있으므로 전 건이 신규 생성되고, 관련 개체 External ID 매핑을 쓸 수 있다.

## 2. Data Loader 설정

| 항목                              | 값                                | 이유                                                                                                                                                 |
| --------------------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Read all CSVs with UTF-8 encoding | ✅ 체크                           | 한글 매장명·Picklist 값. 파일은 BOM 없는 UTF-8                                                                                                       |
| Time Zone                         | `Asia/Seoul`                      | Date 필드(오픈일·점검일)가 하루 밀리는 것을 방지                                                                                                     |
| Batch size                        | 01만 **30**, 나머지 200           | 01 중복 행이 원본과 다른 배치에 들어가야 Duplicate Rule이 동작 (1장 ※ 참고)                                                                          |
| 매핑                              | 헤더가 API Name이므로 Auto-Match  | 참조 컬럼은 v67 형식 `관계명:부모오브젝트-External ID` (예: `Franchise__r:Account-StoreCode__c`). Step 2b에서 같은 관계·필드를 골라야 Auto-Match된다 |
| 실행 사용자                       | 이은석 kai (System Administrator) | OwnerId로 다른 사용자를 지정하려면 해당 권한이 필요                                                                                                  |

Excel로 열면 BOM이 없어서 한글이 깨져 보인다. 파일 내용 문제가 아니므로 Excel에서 저장하지 말고 VS Code에서 확인한다.

## 3. 데이터 구성

### 01 가맹점 (32)

- `StoreCode__c`: HK-0001 ~ HK-0030. 기존 데모 매장(HK-001 ~ 004, 3자리)과 키 형식이 달라 겹치지 않는다.
- 권역: 수도권 15 (HK-0001~0015), 영남 8 (0016~0023), 충청 4 (0024~0027), 호남 3 (0028~0030)
- Owner: 수도권은 김 길동, 그 외는 이은석 kai
- 신규 매장 4곳(BR-01, 오픈일 2026-07-15 이후)

  | 매장       | 매장코드 | 오픈일     |
  | ---------- | -------- | ---------- |
  | 의정부점   | HK-0015  | 2026-07-20 |
  | 인천송도점 | HK-0013  | 2026-08-03 |
  | 구미점     | HK-0023  | 2026-08-24 |
  | 세종점     | HK-0027  | 2026-09-07 |

  4곳 모두 오픈 이후 점검이 2회씩 있다.

### 02 점검 (40)

| 상태     | 판정      | 건수 | 점검일                        |
| -------- | --------- | ---- | ----------------------------- |
| 종료     | 합격      | 18   | 04-14 ~ 08-27                 |
| 지연     | 시정 필요 | 4    | 08-06 ~ 08-24                 |
| 시정중   | 시정 필요 | 10   | 09-02 ~ 10-02                 |
| 점검완료 | 불합격    | 4    | 09-14 ~ 09-22                 |
| 점검예정 | (없음)    | 4    | **10-13 ~ 10-15 (미래 일자)** |

- Record Type: 정기 32 / 불시 8
- 매장 30곳이 모두 1회 이상 점검을 받는다. 그중 10곳은 2회(신규 매장 4곳 + 기존 매장 6곳)이다.
- 점검예정 4건은 "미래 일자" 조건에 맞춰 적재일(10-06) 이후로 잡았다. 그래서 요청 범위(04-01 ~ 10-05)를 벗어난다.

### 03 재점검 (8)

| 재점검              | 원 점검               | 원 점검 판정       | 재점검 판정 | 용도                                  |
| ------------------- | --------------------- | ------------------ | ----------- | ------------------------------------- |
| MIG-INS-0041        | MIG-INS-0028 (노원점) | 불합격             | **불합격**  | 불합격 2회 연속 → 페널티 후보 (BR-08) |
| MIG-INS-0042        | MIG-INS-0031 (부천점) | 불합격             | **불합격**  | 〃                                    |
| MIG-INS-0043 ~ 0044 | 0032, 0033            | 불합격             | 합격        | 시정 성공                             |
| MIG-INS-0045 ~ 0048 | 0023 ~ 0026           | 시정 필요 (시정중) | 합격        | 시정 성공                             |

- 상태는 모두 `재점검완료`이고, 점검일은 원 점검일 + 5 ~ 8일이다.
- 원 점검(02)의 상태는 요청한 분포를 유지하기 위해 갱신하지 않았다.
  실제 운영에서는 재점검 결과에 따라 원 점검 상태가 바뀌어야 한다(D4 이후 자동화 대상).

### 04·05 결과 항목 (144 + 32)

판정이 있는 점검 36건과 재점검 8건에 템플릿 4항목씩 붙인다.
`TemplateItem__c`는 실제 템플릿 Id이고, 항목명·분류·배점·필수 여부는 템플릿 값을 스냅샷한 것이다(BR-11).

| 템플릿           | Id                   | 분류   | 배점 | 필수 |
| ---------------- | -------------------- | ------ | ---- | ---- |
| 냉장고 온도 관리 | `a05dL00001sNrLlQAK` | 위생   | 10   | ✅   |
| 주방 바닥 청결   | `a05dL00001sNrLmQAK` | 위생   | 10   |      |
| 고객 응대 인사   | `a05dL00001sNrLnQAK` | 서비스 | 10   |      |
| 조리 순서 준수   | `a05dL00001sNrLoQAK` | 매뉴얼 | 10   |      |

점수 규칙 (배점 합계 40점):

| 판정      | 총점                 | 미흡 항목 (`IsDeficient__c` = 점수 < 배점의 60%) |
| --------- | -------------------- | ------------------------------------------------ |
| 합격      | 32점 이상 (80%↑)     | 없음                                             |
| 시정 필요 | 24 ~ 31점 (60 ~ 79%) | 일반 항목 1 ~ 2개. 필수 항목은 정상              |
| 불합격    | 무관                 | **필수 항목(냉장고 온도 관리) 미흡** (BR-03)     |

모든 점수는 `0 ≤ Score__c ≤ MaxScore__c` 범위이므로 `ScoreWithinMaxScore`를 통과한다.

> **2026.10.18 변경 (D1 점검표 재구성)** — 미흡 기준을 하나로 맞췄다.
>
> - `IsDeficient__c`는 이제 결과 항목 트리거가 계산한다: **점수 < 배점 × 항목 미흡 기준**
>   (`InspectionRule__mdt` Default의 `DeficiencyRate__c` = 0.6). CSV의 `IsDeficient__c` 값은 저장 시 덮어쓴다.
>   위 표의 「배점의 60%」와 같은 기준이라 이 CSV의 판정 결과는 바뀌지 않는다.
> - `TemplateItem__c`가 있는 행은 insert 때 템플릿의 항목명 · 분류 · 배점 · 필수로 스냅샷을 덮어쓴다(BR-11).
>   위 4항목은 새 점검표(20항목 · 100점) 도입으로 **비활성(사용 중 = false)**이지만, 조회 필드가 Restrict라
>   이 CSV는 그대로 적재된다. 새 점검표 항목은 `scripts/apex/inspectionTemplateReplace.apex` 참고.

## 4. 적재 후 확인

```sql
-- 1) 건수: 가맹점 30(또는 32), 점검 48, 결과 항목 176
SELECT COUNT() FROM Account WHERE StoreCode__c LIKE 'HK-0___'
SELECT COUNT() FROM Inspection__c WHERE InspectionNo__c LIKE 'MIG-INS-%'
SELECT COUNT() FROM InspectionResult__c WHERE Inspection__r.InspectionNo__c LIKE 'MIG-INS-%'

-- 2) 판정과 Roll-Up이 맞는지: 불합격은 ruDeficientRequiredCount__c ≥ 1, 합격은 ruTotalScore__c ≥ 32
SELECT InspectionNo__c, Judgement__c, ruTotalScore__c, ruMaxScore__c, ruDeficientRequiredCount__c
FROM Inspection__c WHERE InspectionNo__c LIKE 'MIG-INS-%' ORDER BY InspectionNo__c
```
