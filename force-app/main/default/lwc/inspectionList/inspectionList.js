/* ======================================================================================
 * @description : 내 점검 목록 (상태 칩 · 검색 · datatable · 페이징)
 * @layer       : LWC
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.13   Kai        Created     최초 작성 (조건 없이 20건 조회)
 *  2026.10.13   Kai        Updated     상태 칩 3개 추가 (클릭 시 즉시 재조회)
 *  2026.10.13   Kai        Updated     가맹점명 검색(디바운스) · 판정 · 점검일 범위 · 검색/초기화 추가
 *  2026.10.13   Kai        Updated     점검일 · 상태 · 판정 서버 정렬 추가 (기본 점검일 ASC)
 *  2026.10.13   Kai        Updated     페이징 추가 (이전/다음 · "n–m / 총 건", 20건)
 *  2026.10.13   Kai        Updated     로딩 spinner · sticky 에러 Toast · 마지막 요청 응답만 반영
 *  2026.10.13   Kai        Updated     D7 설계 초안(Claude Design SC-04) 레이아웃 적용 — 칩 분리 · 카드 분리 · 페이지 번호
 *  2026.10.13   Kai        Updated     칩을 검색 · 초기화와 같은 SLDS 버튼 모양으로 통일
 * ======================================================================================
 *  @see         : docs/d7-lwc-handoff.md §4, InspectionListController.cls
 * ======================================================================================*/
import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import search from "@salesforce/apex/InspectionListController.search";
import { reduceErrors } from "c/ldsUtils";

const PAGE_SIZE = 20;
const KEYWORD_DEBOUNCE_MS = 300;
// NOTE: 정렬 가능 컬럼의 fieldName은 Apex 화이트리스트(SORTABLE_FIELDS)와 같은 API Name이어야 한다
const DEFAULT_SORT_BY = "InspectionDate__c";
const DEFAULT_SORT_DIRECTION = "asc";
const SORT_LABEL_BY_FIELD = {
  InspectionDate__c: "점검일",
  Status__c: "상태",
  Judgement__c: "판정"
};
// DESC: 페이지 번호는 현재 페이지 주변으로 최대 5개만 보인다 (전체 253건 = 13페이지)
const MAX_PAGE_BUTTONS = 5;

// DESC: 칩 → 상태 매핑. 칩 하나가 상태 여러 개를 묶는다. 빈 목록이면 Apex가 상태 조건을 생략한다(= 전체)
const STATUSES_BY_CHIP = {
  todo: ["점검예정"],
  correction: ["시정중", "지연"],
  all: []
};
const CHIP_OPTIONS = [
  { label: "해야 할 점검", value: "todo" },
  { label: "시정 대기", value: "correction" },
  { label: "전체", value: "all" }
];
const DEFAULT_CHIP = "todo";

// NOTE: Judgement__c 선택 목록 값과 같아야 한다. 값이 바뀌면 여기도 고친다 (getPicklistValues 전환은 D8 이후)
const JUDGEMENT_OPTIONS = [
  { label: "전체", value: "" },
  { label: "합격", value: "합격" },
  { label: "시정 필요", value: "시정 필요" },
  { label: "불합격", value: "불합격" }
];

const EMPTY_FILTERS = {
  keyword: "",
  judgement: "",
  dateFrom: null,
  dateTo: null
};

const COLUMNS = [
  {
    label: "점검번호",
    fieldName: "recordUrl",
    type: "url",
    typeAttributes: { label: { fieldName: "Name" }, target: "_self" }
  },
  { label: "가맹점", fieldName: "franchiseName", type: "text" },
  // NOTE: Date 필드는 'date-local' — 'date'로 쓰면 UTC로 해석돼 시간대에 따라 하루 밀릴 수 있다
  {
    label: "점검일",
    fieldName: "InspectionDate__c",
    type: "date-local",
    sortable: true
  },
  { label: "유형", fieldName: "recordTypeName", type: "text" },
  // NOTE: 선택 목록은 SOQL ORDER BY가 가나다순이 아니라 선택 목록 정의 순서로 정렬한다 (상태 = 진행 순서)
  { label: "상태", fieldName: "Status__c", type: "text", sortable: true },
  { label: "총점", fieldName: "ruTotalScore__c", type: "number" },
  { label: "판정", fieldName: "Judgement__c", type: "text", sortable: true }
];

export default class InspectionList extends LightningElement {
  columns = COLUMNS;
  judgementOptions = JUDGEMENT_OPTIONS;
  selectedChip = DEFAULT_CHIP;
  filters = { ...EMPTY_FILTERS };
  sortBy = DEFAULT_SORT_BY;
  sortDirection = DEFAULT_SORT_DIRECTION;
  pageNumber = 1;
  rows = [];
  totalCount = 0;
  isLoading = false;
  validationMessage;
  keywordTimer;
  latestRequestId = 0;

  get totalPages() {
    return Math.max(1, Math.ceil(this.totalCount / PAGE_SIZE));
  }

  get isFirstPage() {
    return this.pageNumber <= 1;
  }

  get isLastPage() {
    return this.pageNumber >= this.totalPages;
  }

  get rangeLabel() {
    if (this.totalCount === 0) {
      return "0건";
    }
    const start = (this.pageNumber - 1) * PAGE_SIZE + 1;
    const end = Math.min(this.pageNumber * PAGE_SIZE, this.totalCount);
    return `${start}–${end} / ${this.totalCount}건`;
  }

  get chips() {
    return CHIP_OPTIONS.map((chip) => {
      const isSelected = chip.value === this.selectedChip;
      return {
        ...chip,
        isSelected: String(isSelected),
        // NOTE: 검색 · 초기화(lightning-button)와 같은 SLDS 버튼 클래스 — 선택 = brand, 나머지 = neutral
        className: isSelected
          ? "slds-button slds-button_brand"
          : "slds-button slds-button_neutral"
      };
    });
  }

  get selectedChipLabel() {
    return CHIP_OPTIONS.find((chip) => chip.value === this.selectedChip)?.label;
  }

  get sortCaption() {
    const direction = this.sortDirection === "asc" ? "오름차순" : "내림차순";
    const isDefault =
      this.sortBy === DEFAULT_SORT_BY &&
      this.sortDirection === DEFAULT_SORT_DIRECTION;
    return `${SORT_LABEL_BY_FIELD[this.sortBy]} ${direction}${isDefault ? " · 급한 것이 위로" : ""}`;
  }

  get pageButtons() {
    const half = Math.floor(MAX_PAGE_BUTTONS / 2);
    const first = Math.max(
      1,
      Math.min(this.pageNumber - half, this.totalPages - MAX_PAGE_BUTTONS + 1)
    );
    const last = Math.min(this.totalPages, first + MAX_PAGE_BUTTONS - 1);
    const buttons = [];
    for (let page = first; page <= last; page++) {
      const isCurrent = page === this.pageNumber;
      buttons.push({
        page,
        ariaCurrent: isCurrent ? "page" : null,
        className: isCurrent
          ? "wsds-inspection-list__page wsds-inspection-list__page--current"
          : "wsds-inspection-list__page"
      });
    }
    return buttons;
  }

  connectedCallback() {
    this.loadInspections();
  }

  disconnectedCallback() {
    clearTimeout(this.keywordTimer);
  }

  async loadInspections() {
    // WARN: 시작일 > 종료일이면 결과가 항상 0건 — 조회하지 않고 바로 알린다
    if (
      this.filters.dateFrom &&
      this.filters.dateTo &&
      this.filters.dateFrom > this.filters.dateTo
    ) {
      this.validationMessage = "점검일 시작이 종료보다 늦습니다.";
      return;
    }
    this.validationMessage = undefined;

    // DESC: 칩 · 검색어를 빠르게 바꾸면 응답이 요청 순서와 다르게 도착할 수 있다 — 마지막 요청의 응답만 반영한다
    const requestId = ++this.latestRequestId;
    this.isLoading = true;
    try {
      const page = await search({ criteria: this.buildCriteria() });
      if (requestId !== this.latestRequestId) {
        return;
      }
      this.rows = page.records.map((record) => this.toRow(record));
      this.totalCount = page.totalCount;
    } catch (error) {
      if (requestId !== this.latestRequestId) {
        return;
      }
      this.rows = [];
      this.totalCount = 0;
      this.showErrorToast(error);
    } finally {
      if (requestId === this.latestRequestId) {
        this.isLoading = false;
      }
    }
  }

  showErrorToast(error) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "점검 목록을 불러오지 못했습니다",
        message: reduceErrors(error).join(", "),
        variant: "error",
        mode: "sticky"
      })
    );
  }

  // NOTE: 빈 문자열은 null로 보낸다 — Apex Date 필드는 ''를 역직렬화하지 못한다
  buildCriteria() {
    return {
      statuses: STATUSES_BY_CHIP[this.selectedChip],
      keyword: this.filters.keyword || null,
      judgement: this.filters.judgement || null,
      dateFrom: this.filters.dateFrom || null,
      dateTo: this.filters.dateTo || null,
      sortBy: this.sortBy,
      sortDir: this.sortDirection,
      pageSize: PAGE_SIZE,
      pageNumber: this.pageNumber
    };
  }

  // DESC: 조건 · 정렬이 바뀌면 결과 집합이 달라지므로 항상 1페이지부터 다시 조회한다
  reloadFromFirstPage() {
    this.pageNumber = 1;
    this.loadInspections();
  }

  handleChipClick(event) {
    const { value } = event.currentTarget.dataset;
    if (value === this.selectedChip) {
      return;
    }
    this.selectedChip = value;
    this.reloadFromFirstPage();
  }

  // DESC: 가맹점명은 입력이 멈추고 300ms 뒤에 조회한다 — 글자마다 Apex를 부르지 않기 위해
  handleKeywordChange(event) {
    this.filters = { ...this.filters, keyword: event.detail.value };
    clearTimeout(this.keywordTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.keywordTimer = setTimeout(() => {
      this.reloadFromFirstPage();
    }, KEYWORD_DEBOUNCE_MS);
  }

  // NOTE: 판정 · 점검일은 값만 담아 두고 [검색]을 눌렀을 때 조회한다
  handleFilterChange(event) {
    const { name } = event.target;
    this.filters = { ...this.filters, [name]: event.detail.value };
  }

  handleSearch() {
    clearTimeout(this.keywordTimer);
    this.reloadFromFirstPage();
  }

  // DESC: 화면에 있는 20건만 정렬하면 다른 페이지 레코드가 빠지므로, 정렬 조건을 서버로 보내 다시 조회한다
  handleSort(event) {
    const { fieldName, sortDirection } = event.detail;
    this.sortBy = fieldName;
    this.sortDirection = sortDirection;
    this.reloadFromFirstPage();
  }

  handlePrevious() {
    this.pageNumber -= 1;
    this.loadInspections();
  }

  handleNext() {
    this.pageNumber += 1;
    this.loadInspections();
  }

  handlePageClick(event) {
    const page = Number(event.currentTarget.dataset.page);
    if (page === this.pageNumber) {
      return;
    }
    this.pageNumber = page;
    this.loadInspections();
  }

  // DESC: 검색 조건만 비운다. 상태 칩 · 정렬은 유지한다
  handleReset() {
    clearTimeout(this.keywordTimer);
    this.filters = { ...EMPTY_FILTERS };
    this.reloadFromFirstPage();
  }

  // DESC: datatable은 Franchise__r.Name 같은 관계 경로를 fieldName으로 못 읽으므로 1단 속성으로 평탄화한다
  toRow(record) {
    return {
      ...record,
      franchiseName: record.Franchise__r?.Name,
      recordTypeName: record.RecordType?.Name,
      recordUrl: `/lightning/r/Inspection__c/${record.Id}/view`
    };
  }
}
