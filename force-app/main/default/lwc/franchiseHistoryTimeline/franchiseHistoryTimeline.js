/* ======================================================================================
 * @description : 매장 이력 타임라인(SC-03) — 가맹점의 점검 · 시정조치 · 페널티를 월별로 시간순 표시
 * @layer       : LWC
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 (확정 시안 docs/design/sc03-franchise-history-mockup.html)
 *  2026.10.14   Kai        Updated     페널티 '반려' 배지를 완료(초록)에서 중립(회색)으로 변경
 * ======================================================================================
 *  @see         : FranchiseHistoryController.cls
 *  @note        : Apex는 데이터만 준다. 상태 → 색(TONE), 날짜 · 기한 문구 조합은 여기서 한다
 * ======================================================================================*/
import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { reduceErrors } from "c/ldsUtils";
import getHistory from "@salesforce/apex/FranchiseHistoryController.getHistory";
import NAME_FIELD from "@salesforce/schema/Account.Name";
import STORE_CODE_FIELD from "@salesforce/schema/Account.StoreCode__c";
import OWNER_NAME_FIELD from "@salesforce/schema/Account.Owner.Name";

const HEADER_FIELDS = [NAME_FIELD, STORE_CODE_FIELD, OWNER_NAME_FIELD];

// NOTE: Apex FranchiseHistoryController.LOOKBACK_MONTHS와 같은 값. 표시 문구용이다
const LOOKBACK_MONTHS = 12;

// DESC: 유형 — Apex eventType → 화면 라벨 · CSS 수식어
const TYPE_META = {
  INSPECTION: { label: "점검", key: "inspection" },
  ACTION: { label: "시정조치", key: "action" },
  PENALTY: { label: "페널티", key: "penalty" }
};

const FILTERS = [
  { value: "all", label: "전체" },
  { value: "INSPECTION", label: "점검" },
  { value: "ACTION", label: "시정조치" },
  { value: "PENALTY", label: "페널티" }
];

// DESC: 배지 색(TONE) — 시안의 TONE 표. 점검은 판정 3색, 시정조치 · 페널티는 진행 중(pending) · 완료(done) · 중립(none)
// NOTE: 시정조치 '지연'만 fail(빨강)로 둔다 — 끝나지 않았지만 기한을 넘긴 상태라 진행 중과 구분해 눈에 띄어야 한다
const TONE_BY_JUDGEMENT = {
  합격: "pass",
  "시정 필요": "correction",
  불합격: "fail"
};
const TONE_BY_ACTION_STATUS = {
  요청: "pending",
  지연: "fail",
  조치완료: "done",
  확인완료: "done"
};
const TONE_BY_PENALTY_STATUS = {
  승인대기: "pending",
  승인: "done",
  // NOTE: 반려는 회색(none). 초록은 좋게 끝남으로 읽힌다. 반려는 페널티 없이 종료된 중립 상태
  반려: "none"
};

const DAY_OF_WEEK = ["일", "월", "화", "수", "목", "금", "토"];
const MS_PER_DAY = 24 * 60 * 60 * 1000;

// NOTE: Apex Date는 "YYYY-MM-DD" 문자열로 온다. new Date(문자열)은 UTC로 해석돼 시간대에 따라 하루 밀리므로 숫자로 직접 나눈다
function parseDate(value) {
  if (!value) {
    return null;
  }
  const [year, month, day] = value.split("-").map(Number);
  return {
    year,
    month,
    day,
    dayOfWeek: new Date(year, month - 1, day).getDay(),
    utc: Date.UTC(year, month - 1, day)
  };
}

function daysBetween(from, to) {
  return Math.round((to.utc - from.utc) / MS_PER_DAY);
}

function pad(value) {
  return String(value).padStart(2, "0");
}

function monthDay(day) {
  return pad(day.month) + "." + pad(day.day);
}

function badgeClass(tone) {
  return "wsds-history__badge wsds-history__badge--" + tone;
}

export default class FranchiseHistoryTimeline extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  selectedFilter = "all";
  events = [];
  isLoaded = false;
  urlsById = {};
  urlRequestId = 0;

  get headerSubtitle() {
    const data = this.franchise?.data;
    const name = getFieldValue(data, NAME_FIELD);
    const storeCode = getFieldValue(data, STORE_CODE_FIELD);
    const ownerName = getFieldValue(data, OWNER_NAME_FIELD);
    return [name, storeCode, ownerName ? "담당 SV " + ownerName : null]
      .filter(Boolean)
      .join(" · ");
  }

  get chips() {
    return FILTERS.map((filter) => {
      const isSelected = filter.value === this.selectedFilter;
      return {
        ...filter,
        count:
          filter.value === "all"
            ? this.events.length
            : this.events.filter((ev) => ev.eventType === filter.value).length,
        // NOTE: 토글 버튼의 눌림 상태를 보조기기에 알린다 — aria 속성 값은 문자열 "true" / "false"
        pressed: String(isSelected),
        className: isSelected
          ? "wsds-history__chip wsds-history__chip--selected"
          : "wsds-history__chip"
      };
    });
  }

  get visibleEvents() {
    return this.selectedFilter === "all"
      ? this.events
      : this.events.filter((ev) => ev.eventType === this.selectedFilter);
  }

  get visibleCount() {
    return this.visibleEvents.length;
  }

  get hasVisibleEvents() {
    return this.visibleCount > 0;
  }

  get isLoading() {
    return Boolean(this.recordId) && !this.isLoaded;
  }

  get footerLabel() {
    return "최근 " + LOOKBACK_MONTHS + "개월 · " + this.visibleCount + "건";
  }

  // DESC: Apex가 날짜 내림차순으로 준 순서를 그대로 두고, 연 · 월이 바뀔 때마다 그룹을 연다
  get groups() {
    const groups = [];
    this.visibleEvents.forEach((ev) => {
      const day = parseDate(ev.eventDate);
      const key = day.year + "-" + day.month;
      let group = groups[groups.length - 1];
      if (!group || group.key !== key) {
        group = {
          key,
          label: day.year + "년 " + day.month + "월",
          events: []
        };
        groups.push(group);
      }
      group.events.push(this.toRow(ev, day));
    });
    return groups;
  }

  // NOTE: 헤더(가맹점명 · 매장코드 · 담당 SV)는 이 레코드 한 건의 필드라 LDS로 읽는다 — Apex 없이 캐시 · FLS ·
  //       저장 후 자동 갱신을 플랫폼이 준다. 타임라인은 세 오브젝트를 2단 관계로 거슬러 모아 합치고 정렬해야 해서
  //       LDS로는 안 되고 Apex가 필요하다
  @wire(getRecord, { recordId: "$recordId", fields: HEADER_FIELDS })
  franchise;

  @wire(getHistory, { franchiseId: "$recordId" })
  handleHistoryWire({ data, error }) {
    if (data) {
      this.events = data;
      this.isLoaded = true;
      this.generateUrls(data);
    } else if (error) {
      this.events = [];
      this.isLoaded = true;
      this.showErrorToast(error);
    }
  }

  handleChipClick(event) {
    this.selectedFilter = event.currentTarget.dataset.value;
  }

  // DESC: 레코드 번호 클릭 → 같은 탭에서 레코드 페이지로 이동. Ctrl · ⌘ · Shift 클릭은 브라우저 기본 동작(새 탭 · 새 창)에 맡긴다
  handleRecordClick(event) {
    if (event.ctrlKey || event.metaKey || event.shiftKey) {
      return;
    }
    event.preventDefault();
    this[NavigationMixin.Navigate](
      this.recordPageRef(event.currentTarget.dataset.id)
    );
  }

  // NOTE: inspectionList는 '/lightning/r/...' URL을 직접 조립했다. 그 경로는 Lightning 데스크톱에서만 맞고 모바일 앱 ·
  //       Experience Cloud에서는 달라진다. 여기서는 GenerateUrl로 실행 환경에 맞는 URL을 받아 href에 넣고
  //       (새 탭 열기 · 주소 복사), 클릭은 Navigate로 처리한다
  async generateUrls(events) {
    const requestId = ++this.urlRequestId;
    try {
      const entries = await Promise.all(
        events.map(async (ev) => [
          ev.recordId,
          await this[NavigationMixin.GenerateUrl](
            this.recordPageRef(ev.recordId)
          )
        ])
      );
      // DESC: 그사이 다른 레코드로 바뀌었으면 늦게 온 결과는 버린다
      if (requestId === this.urlRequestId) {
        this.urlsById = Object.fromEntries(entries);
      }
    } catch {
      // NOTE: URL을 못 받아도 클릭 이동(Navigate)은 동작한다. 새 탭 열기만 안 될 뿐이라 화면을 막지 않는다
      this.urlsById = {};
    }
  }

  recordPageRef(recordId) {
    return {
      type: "standard__recordPage",
      attributes: { recordId, actionName: "view" }
    };
  }

  toRow(ev, day) {
    const type = TYPE_META[ev.eventType];
    const row = {
      recordId: ev.recordId,
      recordNo: ev.recordNo,
      url: this.urlsById[ev.recordId],
      title: ev.title,
      dateLabel: monthDay(day),
      dowLabel: DAY_OF_WEEK[day.dayOfWeek] + "요일",
      typeLabel: type.label,
      typeClass: "wsds-history__type wsds-history__type--" + type.key,
      iconClass: "wsds-history__icon wsds-history__icon--" + type.key,
      isInspection: ev.eventType === "INSPECTION",
      isAction: ev.eventType === "ACTION",
      isPenalty: ev.eventType === "PENALTY",
      isRequired: ev.eventType === "ACTION" && ev.isRequired === true
    };
    if (row.isInspection) {
      return { ...row, ...this.inspectionDetail(ev) };
    }
    if (row.isAction) {
      return { ...row, ...this.actionDetail(ev) };
    }
    return { ...row, ...this.penaltyDetail(ev) };
  }

  // DESC: 점검 — 판정 배지 · 점수 바(합격선 마커) · "27 / 40점 · 달성률 68%" · 필수 미흡 경고
  inspectionDetail(ev) {
    const tone = TONE_BY_JUDGEMENT[ev.judgement] ?? "pending";
    const hasScore = ev.maxScore > 0;
    const percent = hasScore ? Math.round((ev.score / ev.maxScore) * 100) : 0;
    const passPercent = Math.round((ev.passRate ?? 0) * 100);
    return {
      status: ev.judgement || ev.status,
      badgeClass: badgeClass(tone),
      hasScore,
      score: ev.score,
      maxScore: ev.maxScore,
      percent,
      fillClass: "wsds-history__fill wsds-history__fill--" + tone,
      fillStyle: "width: " + Math.min(percent, 100) + "%",
      markerStyle: "left: " + passPercent + "%",
      hasRequiredDeficient: ev.requiredDeficientCount > 0,
      requiredDeficientCount: ev.requiredDeficientCount,
      hasDetail: false,
      hasWarn: false
    };
  }

  // DESC: 시정조치 — "기한 MM.DD · MM.DD 완료 · 재방문 확인 필요", 기한을 넘겨 완료했으면 경고
  actionDetail(ev) {
    const due = parseDate(ev.dueDate);
    const completed = parseDate(ev.completedDate);
    const parts = [];
    if (due) {
      parts.push("기한 " + monthDay(due));
    }
    if (completed) {
      parts.push(monthDay(completed) + " 완료");
    }
    if (ev.requiresRevisit) {
      parts.push("재방문 확인 필요");
    }
    const lateDays = due && completed ? daysBetween(due, completed) : 0;
    return {
      status: ev.status,
      badgeClass: badgeClass(TONE_BY_ACTION_STATUS[ev.status] ?? "pending"),
      detail: parts.join(" · "),
      hasDetail: parts.length > 0,
      warn: lateDays > 0 ? "기한 " + lateDays + "일 초과" : "",
      hasWarn: lateDays > 0
    };
  }

  // DESC: 페널티 — "사유 … · 원 점검 INS-…"
  penaltyDetail(ev) {
    const parts = [];
    if (ev.reason) {
      parts.push("사유 " + ev.reason);
    }
    if (ev.sourceInspectionNo) {
      parts.push("원 점검 " + ev.sourceInspectionNo);
    }
    return {
      status: ev.status,
      badgeClass: badgeClass(TONE_BY_PENALTY_STATUS[ev.status] ?? "pending"),
      detail: parts.join(" · "),
      hasDetail: parts.length > 0,
      warn: "",
      hasWarn: false
    };
  }

  showErrorToast(error) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "매장 이력을 불러오지 못했습니다",
        message: reduceErrors(error).join(", "),
        variant: "error",
        mode: "sticky"
      })
    );
  }
}
