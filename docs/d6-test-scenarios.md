# D6 테스트 시나리오 · Assert 설계

| 항목     | 내용                                                                 |
| -------- | -------------------------------------------------------------------- |
| 문서번호 | 05. 가맹점 점검관리_D6 테스트 시나리오                               |
| 버전     | V1.2                                                                 |
| 작성일자 | 2026.10.12                                                           |
| 프로젝트 | 가맹점 정기점검 관리 — ㈜한끼정성 (SFDC 개발자 온보딩 개인 프로젝트) |
| 작성자   | 이은석(Kai)                                                          |

## 변경 이력

| 버전 | 변경일자   | 작성자 | 변경 내용                                                                                                                 |
| ---- | ---------- | ------ | ------------------------------------------------------------------------------------------------------------------------- |
| V1.0 | 2026.10.12 | Kai    | 최초 작성 — Claude와 시나리오·Assert 문장 설계                                                                            |
| V1.1 | 2026.10.12 | Kai    | 실제 코드 대조 반영 — 기준값 0.8/0.6 확정, BR-03 생성 방식·벌크 SOQL 기준·권한 테스트 이월·배점 null 분리, T-09~T-16 추가 |
| V1.2 | 2026.10.12 | Kai    | S-01~S-07 · T-09~T-16 메서드명 축약, T-11(재점검 VR) · T-13(앞당긴 날짜) · T-16(기대 DML 1) 구체화 — 구현 완료            |

---

## 0. 작성 규칙

- **Apex 식별자는 ASCII만** 허용된다. 메서드 이름에 한글을 쓰면 `Invalid identifier`로 컴파일이 실패한다. 한글은 Assert 메시지 등 **문자열 안**에서만 쓴다.
- 메서드명은 **짧게**(`조건_결과`) 쓰고, 한글 설명은 메서드 바로 위 주석(`// S-01 …`)에 둔다.
- `Assert.areEqual(expected, actual, message)` — **첫 인자가 기대값**. 세 번째 메시지는 필수로 적는다.
- 메시지는 "무엇이 왜 그래야 하는가"를 쓴다. 가능하면 BR 번호를 붙인다.
- 각 시나리오는 **독립된 `@IsTest` 메서드 하나**로 쓴다. 한 메서드에 몰면 첫 Assert 실패 시 나머지가 실행되지 않는다.

### 확정된 기준값 (실제 코드 기준)

| 항목                     | 값                                                                       | 근거                            |
| ------------------------ | ------------------------------------------------------------------------ | ------------------------------- |
| 합격선 `PASS_RATE`       | **0.8**                                                                  | BR-02 · `InspectionService.cls` |
| 시정선 `CORRECTION_RATE` | **0.6**                                                                  | BR-02 · `InspectionService.cls` |
| 판정 Picklist            | `합격` / `시정 필요`(공백 포함) / `불합격`                               | describe 확인                   |
| 점검 상태                | 점검예정 / 점검완료 / 시정중 / 지연 / 재점검완료 / 페널티승인대기 / 종료 | describe 확인                   |

> `Score__c`는 소수 자리 0인 정수 필드다. 배점 100 기준에서 합격선 바로 아래는 **79점**이며, 0.8999 같은 값은 실제 데이터로 만들 수 없다.

---

## A. `InspectionServiceTest` — 판정 로직

`applyJudgements`는 SOQL·DML이 없다. 레코드를 insert하지 않고 메모리 객체로 검증한다.

**Roll-Up 값 주입 방법**: Roll-Up Summary는 읽기 전용이라 생성자로 대입하면 `Field is not writeable`로 컴파일이 막힌다. `JSON.deserialize(JSON.serialize(fieldMap), Inspection__c.class)`로 주입한다.

| ID   | 메서드명                                                             | given (배점 100)                      | Assert                                                                                                                 |
| ---- | -------------------------------------------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| S-01 | `rate80_pass`                                                        | 총점 80, 필수미흡 0                   | `areEqual('합격', …, '득점률 0.8은 경계값으로 합격 (BR-02). 부등호를 >= 에서 > 로 바꾸면 깨져야 한다')`                |
| S-02 | `rate79_correction`                                                  | 총점 79                               | `areEqual('시정 필요', …, '79점은 합격선 미만이므로 시정 필요')`                                                       |
| S-03 | `rate60_correction`                                                  | 총점 60                               | `areEqual('시정 필요', …, '득점률 0.6은 경계값으로 시정 필요 (BR-02)')`                                                |
| S-04 | `rate59_fail`                                                        | 총점 59                               | `areEqual('불합격', …, '59점은 시정선 미만이므로 불합격')`                                                             |
| S-05 | `requiredDeficient_fail`                                             | 총점 100, 필수미흡 1                  | `areEqual('불합격', …, '필수 항목 미흡은 총점과 무관하게 불합격 (BR-03)')`                                             |
| S-06 | `maxScoreZero_keepsJudgement`                                        | 배점 0, **판정에 '합격'을 미리 세팅** | `areEqual('합격', …, '배점이 0이면 기존 판정을 그대로 두어야 함')`                                                     |
| S-07 | `maxScoreNull_keepsJudgement`                                        | 배점 null, 판정 미리 세팅             | `areEqual('합격', …, '배점이 null이어도 예외 없이 건너뛰어야 함')`                                                     |
| S-08 | `judgeInspections_emptyInput_usesNoSoql`                             | `null` · 빈 Set                       | `areEqual(queriesBefore, Limits.getQueries(), '빈 입력에는 SOQL을 쓰지 않아야 함')`                                    |
| S-09 | `judgeInspections_bulk200_usesOneSoqlOneDml`                         | 200건                                 | `areEqual(1, …getQueries() - before, '200건이어도 SOQL 1회')` + `areEqual(1, …getDmlStatements() - before, 'DML 1회')` |
| S-10 | `countInspectionsByFranchise_franchiseWithoutInspection_returnsZero` | 점검 0건 가맹점 포함                  | `areEqual(0, counts.get(emptyId), '점검이 없는 가맹점도 0으로 반환 (키 누락 아님)')`                                   |

### S-06 · S-07 설계 주의

판정 필드는 기본이 null이다. `Assert.isNull`만 쓰면 **"건드리지 않았다"와 "null로 덮어썼다"를 구분할 수 없다.** 판정을 미리 `'합격'`으로 채워 두고 **그 값이 그대로인지** 확인해야 가드(`if (ruMaxScore__c <= 0) continue;`)의 존재가 증명된다.

### 배점 0 / null 구분

Roll-Up SUM은 자식 레코드가 없으면 **0**이 들어간다(null이 아님). 따라서 **null 케이스는 메모리 테스트(S-07)에서만 재현**되며, 트리거 테스트에서는 검증할 수 없다.

---

## B. `InspectionTriggerHandlerTest` — 상태 전이 검증

| ID   | 메서드명                                          | when                          | Assert                                                                                                                                                                                                                                                                              |
| ---- | ------------------------------------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T-01 | `statusTransition_allowed_succeeds`               | 점검예정 → 점검완료           | `isTrue(result.isSuccess(), '허용된 전이는 저장되어야 함')`                                                                                                                                                                                                                         |
| T-02 | `statusTransition_reverseFromCompleted_addsError` | 점검완료 → 점검예정           | `isFalse(result.isSuccess(), '역방향 전이는 막혀야 함')`<br>`isTrue(result.getErrors()[0].getMessage().contains('바꿀 수 없습니다'), '전이 불가 사유가 사용자에게 전달되어야 함')`<br>`areEqual('Status__c', result.getErrors()[0].getFields()[0], '오류는 상태 필드에 걸려야 함')` |
| T-03 | `statusTransition_fromClosed_addsError`           | 종료 → 시정중                 | `isFalse(result.isSuccess(), '종료된 점검은 어떤 상태로도 되돌릴 수 없음')`                                                                                                                                                                                                         |
| T-04 | `statusTransition_fromUnmappedStatus_addsError`   | 페널티승인대기 → 종료         | `isFalse(result.isSuccess(), '전이표에 없는 상태에서 출발하면 모두 차단 (의도된 동작, decision-log 참조)')`                                                                                                                                                                         |
| T-05 | `statusUnchanged_skipsTransitionValidation`       | 상태 그대로, 다른 필드만 수정 | `isTrue(result.isSuccess(), '상태가 바뀌지 않은 저장은 전이 검증 대상이 아님')`                                                                                                                                                                                                     |

**검증 방식**: `update ins;`를 그대로 쓰면 `DmlException`이 터져 테스트가 중단된다. `Database.update(ins, false)`(부분 저장)로 `SaveResult`를 받아 메시지까지 검증한다.

> T-04는 `페널티승인대기` Picklist 값 비활성화 결정(A안)과 연동된다. 비활성화하면 "전이표에 없는 상태 방어"로 성격이 바뀐다. 현재 해당 상태 레코드는 **0건**.

---

## C. `InspectionTriggerHandlerTest` — 판정 세팅 경로

| ID   | 메서드명                                           | 시나리오                                   | Assert                                                                                                                       |
| ---- | -------------------------------------------------- | ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| T-06 | `judgement_onTransitionToCompleted_isSet`          | 점검예정 → 점검완료                        | `areEqual('합격', saved.Judgement__c, '점검완료 전이 시 판정이 자동 세팅되어야 함')`                                         |
| T-07 | `judgement_onChildScoreChange_isRecalculated`      | 이미 점검완료인 점검의 결과 항목 점수 수정 | `areEqual('불합격', saved.Judgement__c, '자식 점수 변경 → Roll-Up 재계산 → 부모 트리거 → 판정 재계산 (Order of Execution)')` |
| T-08 | `judgement_afterCorrectionStage_isNotRecalculated` | 시정중 상태에서 점수 수정                  | `areEqual('시정 필요', saved.Judgement__c, '시정중 이후에는 점수가 바뀌어도 판정을 다시 세팅하지 않는다')`                   |

**T-07이 D5와 이어지는 지점**이다. 결과 항목에 트리거가 없는데도 판정이 바뀌는 경로를 코드로 고정한다.

### BR-03 시나리오(S-05 / T-06 변형) 데이터 생성 방식

`TestDataFactory.createResults`는 `IsDeficient__c = (점수 < 배점)`으로 계산한다. 따라서 **만점이면 미흡이 항상 false**가 되어 "총점 100점 + 필수 미흡 1건"을 바로 만들 수 없다.

→ `doInsert = false`로 결과 항목을 받은 뒤, **필수 항목 하나에 `IsDeficient__c = true`를 직접 세팅하고 insert**한다. Factory에 `doInsert` 옵션을 둔 이유가 이 경우다.

---

## D. `InspectionTriggerHandlerTest` — 최근 정기점검일 집계

`FranchiseInspectionDateService`의 `@testClass`가 이 클래스로 지정되어 있다. 집계 대상은 **RecordType = Regular 이면서 Status != 점검예정**인 점검이다.

| ID   | 메서드명                                   | 시나리오                                                                                                                    | Assert                                                                                                                                     |
| ---- | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| T-09 | `lastDate_regularInsert_set`               | 정기점검(점검완료) insert                                                                                                   | `areEqual(inspectionDate, franchise.LastRegularInspectionDate__c, '정기점검 insert 시 최근 점검일이 세팅되어야 함')`                       |
| T-10 | `lastDate_scheduled_excluded`              | 점검예정 상태                                                                                                               | `isNull(franchise.LastRegularInspectionDate__c, '점검예정은 집계 대상이 아님')`                                                            |
| T-11 | `lastDate_nonRegular_excluded`             | 재점검 · 불시점검 (재점검의 원 점검은 **점검예정** — VR `ReinspectionRequiresOriginal` 충족 + 원 점검 자체가 집계되지 않게) | `isNull(franchise.LastRegularInspectionDate__c, 'Regular 레코드 유형만 집계 대상')`                                                        |
| T-12 | `lastDate_franchiseMoved_bothRecalculated` | 가맹점 A → B                                                                                                                | `isNull(franchiseA…, '점검이 빠진 가맹점은 null로 되돌아가야 함')`<br>`areEqual(inspectionDate, franchiseB…, '새 가맹점에 반영되어야 함')` |
| T-13 | `lastDate_dateMovedEarlier_lowered`        | 점검일을 **더 이른 날짜로** 수정 (늦추면 'MAX(기존, 새 값)' 버그와 구분 불가)                                               | `areEqual(newDate, franchise…, '점검일 수정이 집계에 반영되어야 함')`                                                                      |
| T-14 | `lastDate_latestDeleted_fallsBack`         | 최신 점검 삭제                                                                                                              | `areEqual(olderDate, franchise…, '최신 점검 삭제 시 그 다음 점검일로 내려가야 함')`                                                        |
| T-15 | `lastDate_undeleted_restored`              | 휴지통 복원                                                                                                                 | `areEqual(restoredDate, franchise…, '복원된 점검이 다시 집계되어야 함')`                                                                   |
| T-16 | `lastDate_unrelatedChange_noAccountDml`    | 판정만 수정                                                                                                                 | `areEqual(1, Limits.getDmlStatements() - before, '집계에 영향 없는 수정은 Account DML을 일으키지 않아야 함')` — 테스트 자신의 update 1회만 |

**T-12와 T-14가 핵심**이다. `recalculateLastRegularInspectionDates`는 "대상 가맹점을 전부 null로 채운 뒤 집계 행으로 덮어쓰는" 구조인데, 이 설계가 없으면 삭제·이동 후에도 옛 날짜가 남는다.

**T-16**은 `afterUpdate`의 `affectsDate` 변경 감지 조건을 검증한다. 이게 없으면 "변경 감지를 왜 넣었나"에 대한 근거가 없다.

---

## E. 벌크

| ID   | 메서드명                                | 시나리오                           | Assert                                                                                                                                                                                                      |
| ---- | --------------------------------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T-17 | `bulk200Insert_usesBoundedSoql`         | 200건 insert                       | `isTrue(Limits.getQueries() - before <= 1, '200건 insert에도 SOQL 1회 이하')`<br>`areEqual(10, [SELECT COUNT() FROM Account WHERE LastRegularInspectionDate__c != null], '10개 가맹점 전부 집계되어야 함')` |
| T-18 | `bulk200StatusUpdate_setsAllJudgements` | 200건 상태 update (결과 항목 포함) | `areEqual(200, [SELECT COUNT() FROM Inspection__c WHERE Judgement__c != null], '200건 전부 판정이 세팅되어야 함')`                                                                                          |

**벌크 SOQL 기준은 `<= 1`로 통일한다.** 기준이 느슨하면 루프 안 SOQL 같은 회귀를 놓친다.

**T-18 주의**: 결과 항목 없이 점검만 200건 만들면 `ruMaxScore__c`가 0이라 판정이 건너뛰어진다. 반드시 결과 항목까지 생성해야 한다.

---

## F. 이월 — 권한 테스트

| ID   | 메서드명                                            | 시나리오                    | 상태        |
| ---- | --------------------------------------------------- | --------------------------- | ----------- |
| T-19 | `visibility_svUser_seesOwnFranchiseInspectionsOnly` | `System.runAs(svUser)` 조회 | **D7 이월** |

이월 사유와 작성 시 주의:

- 점검 OWD가 **Private**라 테스트 데이터의 `OwnerId`를 SV로 지정하지 않으면 SV는 아무것도 보지 못한다.
- Platform 라이선스 **잔여 0**이라 테스트 안에서 User를 insert하면 실패할 가능성이 크다. 기존 테스트 사용자(김 길동 SV)를 SOQL로 조회해 `runAs`에 쓰는 방식이 안전하다.
- 기대값은 "담당 점검 N건은 보이고 타 SV 점검은 0건"처럼 **숫자로** 정한다. "기대치와 일치"로는 Assert를 쓸 수 없다.

---

## G. 오늘 우선순위

| 구분                                | 항목                                                         |
| ----------------------------------- | ------------------------------------------------------------ |
| **필수** (커버리지 85% + 발표 증빙) | S-01~S-05, S-09, T-01, T-02, T-06, T-07, T-09, T-12, T-17    |
| 여유 있으면                         | S-06~S-08, S-10, T-03~T-05, T-08, T-10~T-11, T-13~T-16, T-18 |
| 이월                                | T-19 (D7)                                                    |

---

## H. 발표용 증빙 — "이 테스트는 어떤 버그를 잡는가"

커버리지 숫자보다 강력한 증거다. 실험 후 **반드시 원복하고 재배포**한다 (`git diff`로 확인).

| 실험        | 깨뜨릴 코드                                                       | 기대 결과                                             |
| ----------- | ----------------------------------------------------------------- | ----------------------------------------------------- |
| 가드 제거   | `applyJudgements`의 `if (ruMaxScore__c <= 0) continue;` 주석 처리 | **S-06·S-07만** 실패, 나머지 초록                     |
| 부등호 변경 | `decideJudgement`의 `rate >= PASS_RATE` → `rate > PASS_RATE`      | **S-01만** 실패                                       |
| CMDT 전환   | 상수 → `InspectionRule__mdt`                                      | 전환 전후 **모두 초록** = 동작이 바뀌지 않았다는 증명 |
