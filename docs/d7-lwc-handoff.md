# D7 LWC 작업 지시서 — 한끼정성 (2026-10-13)

설계 근거: Claude Design 「D7 LWC 화면 설계 초안」(SC-02 점검 입력 · SC-04 내 점검 목록 · Spec).
Claude Code는 그 보드를 볼 수 없으므로 필요한 내용을 여기에 옮겼다. 이 문서가 오늘의 기준이다.
개념·판단 근거는 `docs/한끼정성_Day7_핵심개념.html` §3~§6.

## 1. 완성 기준 — 내일 09:00 시연 (전부 김 길동 SV 계정)

| #   | 장면                                                         | 보여주는 것                                     |
| --- | ------------------------------------------------------------ | ----------------------------------------------- |
| 1   | 내 점검 목록 — 담당 매장만 보인다                            | datatable · 검색 · BR-10 공유 규칙              |
| 2   | 상태 칩을 **전체**로 → 12건, 2페이지                         | 정렬 · 페이징                                   |
| 3   | 점검 클릭 → 상세                                             | record-form · 판정 패널 `@wire`                 |
| 4   | **점검완료 레코드**의 상태를 점검예정으로 되돌려 저장 → 실패 | 에러 Toast(sticky) · `reduceErrors` · 필드 오류 |
| 5   | 상태 되돌리고 점수 고쳐 저장 → 성공                          | 성공 Toast · 판정 갱신                          |

> 시연 4는 반드시 **상태가 점검완료인 레코드**로 한다. 점검중 레코드는 전이표상 점검예정으로 돌아갈 수 있을 수 있다 — `InspectionTriggerHandler`의 전이표를 확인.

## 2. 오늘 범위 / D8 이후

| 구분 | 오늘 구현                                                                                                  | D8 이후 (오늘은 설계 메모만)                                                                                                |
| ---- | ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| 상세 | `inspectionDetail` (record-form + Toast), `inspectionJudgementPanel` (`@wire(getRecord)` 읽기 전용)        | `inspectionResultEditor` → `inspectionResultRow` 반복, `InspectionResultController.getResults/saveResults`, BR-04 사진 필수 |
| 목록 | `inspectionList` 한 컴포넌트 (상태 칩 · 검색 · datatable · 페이징 포함), `InspectionListController.search` | `inspectionStatusChips` · `inspectionSearchBar` · `inspectionPaginator`로 분리, 칩 건수 집계                                |
| 기타 | —                                                                                                          | 모바일(등급 버튼), SC-05 권역 팀장 화면                                                                                     |

## 3. 결정 사항 (Spec 「아직 정하지 않은 것」 해소)

- 저장 후 갱신: record-form·`getRecord`는 LDS가 자동 갱신. Apex DML 뒤에는 `notifyRecordUpdateAvailable([{recordId}])`. Apex `@wire` 결과 갱신은 `refreshApex` (D8 `getResults`에서 필요).
- 목록 기본 정렬: `InspectionDate__c ASC` (급한 것이 위). 정렬·페이징은 **서버**(`ORDER BY` + `LIMIT/OFFSET`).
- 검색어는 바인드 변수, 정렬 컬럼은 화이트리스트. 동적 SOQL은 `Database.query`.
- 상태 칩 건수(「해야 할 점검 5」)는 오늘 생략. 칩은 상태 필터 역할만 한다.
- 모바일·SC-05는 D8 이후.

## 4. 컴포넌트 — 오늘

### `inspectionDetail` — target `lightning__RecordPage` (Inspection__c)

- `@api recordId`
- `lightning-record-form` `object-api-name="Inspection__c"` `layout-type="Full"` `mode="view"` `onsuccess` `onerror`
- `onsuccess` → 성공 Toast(dismissable). `onerror` → `reduceErrors(event.detail)` → 에러 Toast(**sticky**)
- 자식: `<c-inspection-judgement-panel record-id={recordId}>`

### `inspectionJudgementPanel` — 읽기 전용

- `@api recordId`
- `@wire(getRecord, { recordId: '$recordId', fields })` — `ruTotalScore__c`, `ruMaxScore__c`, `ruDeficientRequiredCount__c`, `Judgement__c`
- 표시: 총점/배점, 달성률 바(합격선 80%), 판정 배지(합격 초록 · 시정 필요 주황 · 불합격 빨강), 필수 미흡 건수
- 필드 API Name은 `force-app/main/default/objects/Inspection__c/fields/`로 확인한다. 위 이름은 D6 자료 기준이며 확정 아님.

### `inspectionList` — target `lightning__AppPage`

- 상태 칩 3개 → `statuses`(List). **칩 클릭 = 즉시 재조회**. 칩 → 상태 매핑은 LWC가 가진다

  | 키           | 라벨         | `statuses`                      |
  | ------------ | ------------ | ------------------------------- |
  | `todo`       | 해야 할 점검 | `['점검예정']`                  |
  | `correction` | 시정 대기    | `['시정중', '지연']`            |
  | `all`        | 전체         | `[]` (빈 목록 = 상태 조건 없음) |

  > 설계 초안의 「점검중」 칩은 뺐다. 요건 정의서 V1.0 §3의 상태 7개에 없는 값이다 (설계 초안 오류).

- 검색: 가맹점명(`lightning-input`, 디바운스 300ms) · 판정(`lightning-combobox`) · 점검일 시작/종료 · 검색 · 초기화 버튼
- `lightning-datatable` 컬럼: 점검번호(url → 레코드) · 가맹점(`franchiseName` 평탄화) · 점검일 · 유형 · 상태 · 총점 · 판정. `sortable` 점검일·상태·판정. `hide-checkbox-column`
- 페이징: 이전/다음 + "1–20 / 52건". `pageSize` 20
- 로딩 `lightning-spinner`, 에러 Toast(sticky)
- 호출 방식: **imperative** (`await search({...})`)

### 자식→부모 이벤트 설계 메모 (오늘 구현 안 함)

| 컴포넌트                 | @api (부모→자식)                         | 이벤트 (자식→부모)                    |
| ------------------------ | ---------------------------------------- | ------------------------------------- |
| `inspectionResultEditor` | `results` · `readOnly`                   | `resultchange` · detail: 바뀐 행 전체 |
| `inspectionResultRow`    | `result` · `maxScore` · `isRequired`     | `rowchange` → editor가 받아 다시 올림 |
| `inspectionStatusChips`  | `counts` · `selected`                    | `statuschange` · detail: 고른 상태    |
| `inspectionSearchBar`    | `criteria`                               | `searchchange` · detail: 조건 전체    |
| `inspectionPaginator`    | `pageNumber` · `pageSize` · `totalCount` | `pagechange` · detail: 페이지 번호    |

원칙: 자식은 자기 데이터를 고치지 않는다. 바뀐 값만 올리고 수정·저장은 부모가 한다. 이벤트 이름은 전부 소문자.

## 5. Apex — 오늘

```apex
public with sharing class InspectionListController {

    public class SearchCriteria {           // LWC에서 객체 하나로 넘김
        @AuraEnabled public String keyword;
        @AuraEnabled public List<String> statuses; // null · 빈 목록이면 전체. WHERE Status__c IN :statuses
        @AuraEnabled public String judgement;   // null이면 전체
        @AuraEnabled public Date dateFrom;
        @AuraEnabled public Date dateTo;
        @AuraEnabled public String sortBy;      // 화이트리스트 검증
        @AuraEnabled public String sortDir;     // asc | desc
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer pageNumber; // 1부터
    }

    public class InspectionPageWrapper {
        @AuraEnabled public List<Inspection__c> records;
        @AuraEnabled public Integer totalCount;
    }

    @AuraEnabled(cacheable=true)
    public static InspectionPageWrapper search(SearchCriteria criteria) { ... }
}
```

- `with sharing` 필수 — BR-10(담당 매장만)은 공유 규칙이 거르므로 코드에서 OwnerId 조건을 넣지 않는다.
- `totalCount`는 같은 WHERE로 `COUNT()` 한 번 더.
- `OFFSET` 최대 2,000 — 주석에 한계를 적는다.
- 테스트 `InspectionListControllerTest`: 검색 결과 · 페이징 경계(2페이지 첫 건) · 정렬 화이트리스트 거부 · 벌크 200건.

## 6. Claude Code 프롬프트 — 순서대로, 하나 끝나고 확인한 뒤 다음

### 덩어리 1 — 상세 화면 (목표 60분)

```
docs/d7-lwc-handoff.md §4의 inspectionDetail과 inspectionJudgementPanel을 만들어줘.
순서:
1. sf lightning generate component로 두 컴포넌트 생성. meta.xml은 isExposed=true, target은 lightning__RecordPage만.
2. inspectionDetail은 record-form만 넣고 먼저 배포 — 내가 App Builder에 배치해서 뜨는지 확인할게.
3. 확인되면 onsuccess/onerror Toast 추가. reduceErrors는 LWC Recipes의 ldsUtils를 lwc/ldsUtils/로 가져와서 import.
4. inspectionJudgementPanel은 @wire(getRecord)로. 필드 API Name은 objects/Inspection__c/fields/에서 확인해서 써.
각 단계마다 배포 명령과 결과를 보여주고 멈춰. 전부 한 번에 하지 마.
```

→ 사람이 직접: 점검 레코드 열기 → ⚙ Edit Page → 「점검 상세」 드래그 → Save → Activation.
→ 확인: 폼이 뜨는가 / 점검완료 레코드를 점검예정으로 바꿔 저장 → 에러 Toast가 D5 메시지를 보여주는가.

### 덩어리 2 — Apex 컨트롤러 (목표 45분)

```
docs/d7-lwc-handoff.md §5의 InspectionListController를 만들어줘.
- with sharing, cacheable=true, 동적 SOQL은 바인드 변수 + 정렬 컬럼 화이트리스트.
- InspectionListControllerTest도 같이: 검색 결과 · 페이징 경계 · 정렬 화이트리스트 거부 · 벌크 200건. TestDataFactory 사용.
- 배포 후 sf apex run test로 통과와 커버리지 보여줘.
- 그다음 Execute Anonymous로 search를 한 번 호출해서 결과 레코드 수를 보여줘. LWC는 아직 만들지 마.
```

→ 확인: 테스트 통과 · org 커버리지 85% 유지 · Anonymous 호출 결과가 비어 있지 않은가.

### 덩어리 3 — 목록 화면 (목표 120분)

```
docs/d7-lwc-handoff.md §4의 inspectionList를 만들어줘. target은 lightning__AppPage.
순서대로, 각 단계 끝에 배포하고 멈춰:
1. datatable에 search 결과 20건만 — 조건 없이. Franchise__r.Name은 franchiseName으로 평탄화.
2. 상태 칩 4개 → 클릭하면 재조회.
3. 가맹점명 검색(디바운스 300ms) + 판정 콤보 + 점검일 범위 + 검색/초기화 버튼.
4. 정렬: sortable + onsort → 서버 재조회. 기본 InspectionDate__c ASC.
5. 페이징: 이전/다음 + "n–m / 총 건". pageSize 20.
6. spinner와 에러 Toast(sticky).
1번 끝나면 내가 App Page 만들어 배치할게.
```

→ 사람이 직접: Setup → Lightning App Builder → New → App Page → 「내 점검」 → 배치 → Save → Activation → 앱에 탭 추가.
→ 확인: 탭이 보이는가 / 칩 「전체」로 바꾸면 2페이지가 되는가 / F12 Console에 빨간 에러 없는가.

### 마무리 (17:00)

```
오늘 만든 것 기준으로 docs/daily-log.md에 D7 항목을 추가하고,
docs/decision-log.md에 아래 5줄을 D7로 추가한 뒤 네가 구현하면서 내린 결정을 2~3줄 덧붙여줘.
(여기에 브라우저 Claude가 준 5줄을 붙여넣기)
그다음 git add force-app docs 하고 커밋해줘. 메시지는 commit.md 형식으로.
```

## 7. 퇴근 전 체크

- [ ] Setup → Lightning Components에 `inspectionDetail` · `inspectionJudgementPanel` · `inspectionList` · `ldsUtils`
- [ ] 점검 레코드 페이지: 폼 + 판정 패널 보임, 저장 성공 Toast
- [ ] 점검완료 → 점검예정 저장 → D5 메시지가 에러 Toast(sticky)로 **← 발표 데모**
- [ ] 「내 점검」 탭: 검색 · 정렬 · 페이징 동작, 칩 「전체」에서 2페이지
- [ ] F12 Console 빨간 에러 없음
- [ ] `sf apex run test --test-level RunLocalTests --code-coverage` 85% 이상
- [ ] daily-log · decision-log 갱신 · 커밋

## 8. 시간이 모자라면 버리는 순서

페이징 → 점검일 범위 필터 → 정렬 → 판정 콤보. **못 버리는 것**: 상세 폼 + 에러 Toast, 목록에 표가 뜨는 것.

---

작성 이은석(Kai) · 2026-10-13 · 설계 초안(Claude Design)과 범위 조정은 AI와 함께, 요건(SC-02 · SC-04 · BR-10) 대조는 본인 확인 · 필드 API Name은 구현 시 메타데이터로 확정
