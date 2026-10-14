# D6 필드 레퍼런스 (TestDataFactory용)

| 항목     | 내용                                                                 |
| -------- | -------------------------------------------------------------------- |
| 문서번호 | 04. 가맹점 점검관리_D6 필드 레퍼런스                                 |
| 버전     | V1.0                                                                 |
| 작성일자 | 2026.10.12                                                           |
| 프로젝트 | 가맹점 정기점검 관리 — ㈜한끼정성 (SFDC 개발자 온보딩 개인 프로젝트) |
| 작성자   | 이은석(Kai)                                                          |

## 변경 이력

| 버전 | 변경일자   | 작성자 | 변경 내용                                                                                          |
| ---- | ---------- | ------ | -------------------------------------------------------------------------------------------------- |
| V1.0 | 2026.10.12 | Kai    | 최초 작성 — `scripts/apex/describe-fields.apex` 실행 결과(kai-dev)로 커스텀 오브젝트 4종 필드 확정 |

---

## 0. 조사 방법

- 스크립트: `scripts/apex/describe-fields.apex` (`sf apex run --file scripts/apex/describe-fields.apex -o kai-dev`)
- 대상: 커스텀 필드(`isCustom()`) + Name 필드. 표준 시스템 필드(Id, OwnerId, CreatedDate 등)는 제외
- **필수 판정**: `!isNillable() && isCreateable() && !isDefaultedOnCreate()`
- `isCreateable()`은 실행 사용자(시스템 관리자) FLS 기준이다. 다른 사용자로 `System.runAs` 하면 결과가 달라질 수 있다.
- ERD 문서의 Label 기준 API Name은 이 결과로 대체한다.

## 1. TestDataFactory가 반드시 세팅해야 하는 필드

### 1.1 describe 기준 필수 (미입력 시 insert 실패)

| 오브젝트                    | 필드                  | 값                             |
| --------------------------- | --------------------- | ------------------------------ |
| `Inspection__c`             | `Franchise__c`        | Account Id                     |
| `InspectionResult__c`       | `Inspection__c`       | Inspection\_\_c Id (M-D)       |
| `InspectionTemplateItem__c` | _(없음)_              | -                              |
| `CorrectiveAction__c`       | `InspectionResult__c` | InspectionResult\_\_c Id (M-D) |

생성 순서: **Account → Inspection\_\_c → InspectionResult\_\_c → CorrectiveAction\_\_c** (템플릿은 독립, 결과 항목의 `TemplateItem__c`는 선택)

### 1.2 describe로 잡히지 않는 제약 (데이터에 따라 실패)

| 오브젝트              | 제약                         | 조건                                                                            | 근거                              |
| --------------------- | ---------------------------- | ------------------------------------------------------------------------------- | --------------------------------- |
| `Inspection__c`       | `OriginalInspection__c` 필수 | Record Type이 `Reinspection`일 때                                               | VR `ReinspectionRequiresOriginal` |
| `InspectionResult__c` | `Score__c` 범위              | `Score__c < 0` 또는 (`MaxScore__c` 있음 AND `Score__c > MaxScore__c`) 이면 실패 | VR `ScoreWithinMaxScore`          |
| `Inspection__c`       | `Status__c` 변경 제한        | update 시 허용되지 않은 상태 전이는 `addError`                                  | `InspectionTriggerHandler` (D5)   |

### 1.3 세팅 불가 필드 (생성 불가 — 값을 넣지 말 것)

| 오브젝트                                                      | 필드                                                              | 이유                           |
| ------------------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------ |
| `Inspection__c`                                               | `ruTotalScore__c`, `ruMaxScore__c`, `ruDeficientRequiredCount__c` | Roll-Up Summary                |
| `Inspection__c`, `InspectionResult__c`, `CorrectiveAction__c` | `Name`                                                            | 생성 불가 (Auto Number로 보임) |

> `InspectionTemplateItem__c.Name`은 생성 가능한 Text지만 필수 판정에서 빠졌다(`isDefaultedOnCreate()`가 true로 판정된 것으로 보임). 항목명이 테스트 의미를 가지므로 TestDataFactory에서는 명시적으로 세팅하는 것을 권장.

---

## 2. 오브젝트별 필드

표기: 필수·생성 `Y` = 해당, `-` = 해당 없음

### 2.1 `Inspection__c` (점검)

| API Name                      | 타입      | 필수  | 생성 | 참조대상 / Picklist 값                                             |
| ----------------------------- | --------- | ----- | ---- | ------------------------------------------------------------------ |
| `Franchise__c`                | REFERENCE | **Y** | Y    | → Account                                                          |
| `InspectionDate__c`           | DATE      | -     | Y    |                                                                    |
| `InspectionNo__c`             | STRING    | -     | Y    |                                                                    |
| `Judgement__c`                | PICKLIST  | -     | Y    | 합격, 시정 필요, 불합격                                            |
| `Name`                        | STRING    | -     | -    |                                                                    |
| `OriginalInspection__c`       | REFERENCE | -     | Y    | → Inspection\_\_c                                                  |
| `Status__c`                   | PICKLIST  | -     | Y    | 점검예정, 점검완료, 시정중, 지연, 재점검완료, 페널티승인대기, 종료 |
| `ruDeficientRequiredCount__c` | DOUBLE    | -     | -    |                                                                    |
| `ruMaxScore__c`               | DOUBLE    | -     | -    |                                                                    |
| `ruTotalScore__c`             | DOUBLE    | -     | -    |                                                                    |

### 2.2 `InspectionResult__c` (점검 결과 항목)

| API Name          | 타입      | 필수  | 생성 | 참조대상 / Picklist 값        |
| ----------------- | --------- | ----- | ---- | ----------------------------- |
| `Category__c`     | PICKLIST  | -     | Y    | 위생, 서비스, 매뉴얼          |
| `Inspection__c`   | REFERENCE | **Y** | Y    | → Inspection\_\_c             |
| `IsDeficient__c`  | BOOLEAN   | -     | Y    |                               |
| `IsRequired__c`   | BOOLEAN   | -     | Y    |                               |
| `ItemName__c`     | STRING    | -     | Y    |                               |
| `MaxScore__c`     | DOUBLE    | -     | Y    |                               |
| `Name`            | STRING    | -     | -    |                               |
| `Score__c`        | DOUBLE    | -     | Y    |                               |
| `TemplateItem__c` | REFERENCE | -     | Y    | → InspectionTemplateItem\_\_c |

### 2.3 `InspectionTemplateItem__c` (점검 항목 템플릿)

| API Name        | 타입     | 필수 | 생성 | 참조대상 / Picklist 값 |
| --------------- | -------- | ---- | ---- | ---------------------- |
| `Category__c`   | PICKLIST | -    | Y    | 위생, 서비스, 매뉴얼   |
| `IsActive__c`   | BOOLEAN  | -    | Y    |                        |
| `IsRequired__c` | BOOLEAN  | -    | Y    |                        |
| `MaxScore__c`   | DOUBLE   | -    | Y    |                        |
| `Name`          | STRING   | -    | Y    |                        |
| `SortOrder__c`  | DOUBLE   | -    | Y    |                        |

### 2.4 `CorrectiveAction__c` (시정조치)

| API Name              | 타입      | 필수  | 생성 | 참조대상 / Picklist 값         |
| --------------------- | --------- | ----- | ---- | ------------------------------ |
| `CompletedDate__c`    | DATE      | -     | Y    |                                |
| `DueDate__c`          | DATE      | -     | Y    |                                |
| `InspectionResult__c` | REFERENCE | **Y** | Y    | → InspectionResult\_\_c        |
| `Name`                | STRING    | -     | -    |                                |
| `RequiresRevisit__c`  | BOOLEAN   | -     | Y    |                                |
| `Status__c`           | PICKLIST  | -     | Y    | 요청, 조치완료, 지연, 확인완료 |
