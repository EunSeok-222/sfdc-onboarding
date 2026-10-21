/* ======================================================================================
 * @description : 점검 결과 입력 (SC-02) — 분류별 결과 항목에 점수를 넣고 한 번에 저장한다. 미흡은 트리거가 판정(읽기 전용)
 * @layer       : LWC
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 26-10-18 SC-02 점검 결과 입력
 *  2026.10.18   Kai        Updated     26-10-18 좁은 영역 세로 배치 by Kai
 *  2026.10.19   Kai        Updated     시정 단계부터 점수 잠금 안내 한 줄(검증 규칙 ScoreLockedAfterCompletion과 같은 기준)
 *  2026.10.19   Kai        Updated     점검 상태 구독(getRecord) — 상태가 바뀌면 결과 시트 다시 받기 · 새로고침 핸들러 ·
 *                                      getRecordNotifyChange → notifyRecordUpdateAvailable
 * ======================================================================================
 *  @see         : InspectionResultController.cls, inspectionJudgementPanel(저장 뒤 getRecord로 갱신),
 *                 inspectionDetail(조치 추가 뒤 점검 레코드 갱신 알림)
 *  @note        : 범위 밖 — 사진 첨부(BR-04) · 임시 저장/완료 분리 · 완료 미리보기 · 행 추가/삭제. 버튼은 「저장」 하나
 * ======================================================================================*/
import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import {
  getRecord,
  getFieldValue,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import {
  registerRefreshHandler,
  unregisterRefreshHandler
} from "lightning/refresh";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { reduceErrors } from "c/ldsUtils";
import getResults from "@salesforce/apex/InspectionResultController.getResults";
import saveResults from "@salesforce/apex/InspectionResultController.saveResults";
import STATUS_FIELD from "@salesforce/schema/Inspection__c.Status__c";

// NOTE: 점수를 고칠 수 있는 점검 상태 — 컨트롤러 EDITABLE_STATUSES · 검증 규칙 ScoreLockedAfterCompletion과 같은 기준
const EDITABLE_STATUSES = ["점검예정", "점검완료"];
const LOCK_NOTICE = "시정 단계부터는 점수를 고칠 수 없습니다(판정 고정).";

export default class InspectionResultEditor extends LightningElement {
  @api recordId;
  // NOTE: 레코드 페이지가 넣어 주는 영역 폭(SMALL · MEDIUM · LARGE). App Page 등에서는 비어 있다
  @api flexipageRegionWidth;

  // DESC: 화면에서 고친 점수만 담는다 — 결과 항목 Id → 점수(비우면 null)
  draftScoresById = {};
  results = [];
  inspectionStatus;
  isReadOnly = true;
  isLoaded = false;
  isSaving = false;
  wiredSheet;
  // DESC: LDS(getRecord)로 마지막에 받은 점검 상태 — 처음 값 이후 바뀌었는지 비교용
  recordStatus;
  refreshHandlerId;

  @wire(getResults, { inspectionId: "$recordId" })
  wiredResults(value) {
    this.wiredSheet = value;
    const { data, error } = value;
    if (data) {
      this.results = data.results;
      this.inspectionStatus = data.inspectionStatus;
      this.isReadOnly = data.isReadOnly;
      // NOTE: 잠긴 시트의 비활성 입력칸에 저장하지 않은 입력값이 남아 보이지 않게 한다
      if (data.isReadOnly) {
        this.draftScoresById = {};
      }
      this.isLoaded = true;
    } else if (error) {
      this.isLoaded = true;
      this.toast(
        "결과 항목을 불러오지 못했습니다",
        reduceErrors(error).join(", "),
        "error"
      );
    }
  }

  // DESC: 점검 상태를 LDS로 구독한다. 조치 추가(After-Save Flow → 시정중)처럼 다른 곳에서 상태가 바뀌어
  //       notifyRecordUpdateAvailable이 오면 이 wire가 다시 불린다 → 처음 값 이후 바뀌었을 때만 결과 시트를 다시 받는다
  // NOTE: 결과 시트는 @wire(Apex)라 LDS 레코드 갱신에 따라 자동으로 다시 읽히지 않는다. 오류는 결과 시트 wire가 알린다
  @wire(getRecord, { recordId: "$recordId", fields: [STATUS_FIELD] })
  wiredInspection({ data }) {
    if (!data) {
      return;
    }
    const status = getFieldValue(data, STATUS_FIELD);
    const isChanged =
      this.recordStatus !== undefined && this.recordStatus !== status;
    this.recordStatus = status;
    if (isChanged) {
      this.refreshSheet().catch((error) =>
        this.toast(
          "결과 항목을 다시 불러오지 못했습니다",
          reduceErrors(error).join(", "),
          "error"
        )
      );
    }
  }

  // NOTE: 페이지의 Lightning 새로고침(빠른 작업 저장 등)에 참여하도록 핸들러를 등록하고, 화면을 떠나면 해제한다
  connectedCallback() {
    this.refreshHandlerId = registerRefreshHandler(
      this,
      this.refreshSheet.bind(this)
    );
  }

  disconnectedCallback() {
    unregisterRefreshHandler(this.refreshHandlerId);
  }

  get hasResults() {
    return this.results.length > 0;
  }

  // DESC: 시정 단계(시정중 · 지연 · 재점검완료 · 종료)면 잠금 안내 한 줄. 권한이 없어 읽기 전용인 경우는 안내하지 않는다
  get lockNotice() {
    return this.isLoaded &&
      this.inspectionStatus &&
      !EDITABLE_STATUSES.includes(this.inspectionStatus)
      ? LOCK_NOTICE
      : null;
  }

  // DESC: 사이드바 등 좁은 영역이면 세로 배치. 값이 없으면 넓은 배치
  get isNarrow() {
    return this.flexipageRegionWidth === "SMALL";
  }

  // NOTE: slds-medium-size_*는 화면 폭 기준이라 좁은 사이드바에서도 6/3/3으로 나뉜다 — 영역 폭(isNarrow)으로 명시 분기
  //       좁을 때: 1줄 항목명 · 필수 / 2줄 점수 · 배점 · 미흡(오른쪽 끝)
  get nameCellClass() {
    return this.isNarrow
      ? "slds-col slds-size_1-of-1 slds-var-p-top_xx-small result-name_narrow"
      : "slds-col slds-size_6-of-12 slds-var-p-vertical_xx-small";
  }

  get scoreCellClass() {
    return this.isNarrow
      ? "slds-col slds-grid slds-grid_vertical-align-center slds-var-p-vertical_xx-small"
      : "slds-col slds-size_3-of-12 slds-grid slds-grid_vertical-align-center";
  }

  get flagCellClass() {
    return this.isNarrow
      ? "slds-col slds-grow-none slds-var-p-left_small slds-text-align_right"
      : "slds-col slds-size_3-of-12 slds-text-align_right";
  }

  // NOTE: 종료된 점검 · 점수 편집 권한이 없는 사용자는 저장 버튼 자체를 숨긴다(입력칸은 disabled)
  get showSaveButton() {
    return this.hasResults && !this.isReadOnly;
  }

  // DESC: 분류별 묶음 — 서버가 분류 → 템플릿 순서로 정렬해 보내므로 순서를 그대로 쓴다
  get groups() {
    const groups = [];
    const byCategory = {};
    this.results.forEach((result) => {
      const category = result.category || "기타";
      if (!byCategory[category]) {
        byCategory[category] = { category, maxTotal: 0, rows: [] };
        groups.push(byCategory[category]);
      }
      const score = this.currentScore(result);
      const group = byCategory[category];
      group.maxTotal += result.maxScore || 0;
      group.rows.push({
        ...result,
        score,
        rowClass: this.isBlank(score)
          ? "result-row result-row_blank slds-grid slds-wrap slds-grid_vertical-align-center"
          : "result-row slds-grid slds-wrap slds-grid_vertical-align-center"
      });
    });
    groups.forEach((group) => {
      group.title = `${group.category} (배점 ${group.maxTotal}점)`;
    });
    return groups;
  }

  get filledSummary() {
    const filled = this.results.filter(
      (result) => !this.isBlank(this.currentScore(result))
    ).length;
    return `${filled} / ${this.results.length} 입력됨`;
  }

  get changedIds() {
    return Object.keys(this.draftScoresById).filter((id) => {
      const original = this.results.find((result) => result.id === id);
      return (
        original && this.normalize(original.score) !== this.draftScoresById[id]
      );
    });
  }

  get isSaveDisabled() {
    return this.isSaving || this.changedIds.length === 0;
  }

  handleScoreChange(event) {
    const id = event.target.dataset.id;
    this.draftScoresById = {
      ...this.draftScoresById,
      [id]: this.normalize(event.target.value)
    };
  }

  async handleSave() {
    // NOTE: 범위(0 ~ 배점) · 정수는 입력칸이 먼저 막는다. 서버 검증 규칙(ScoreWithinMaxScore)은 최종 방어선
    const inputs = [...this.template.querySelectorAll("lightning-input")];
    const allValid = inputs.reduce(
      (valid, input) => input.reportValidity() && valid,
      true
    );
    if (!allValid) {
      this.toast(
        "점수를 확인하세요",
        "0 이상 배점 이하의 정수만 입력할 수 있습니다.",
        "error"
      );
      return;
    }
    const ids = this.changedIds;
    const scores = ids.map((id) => this.draftScoresById[id]);
    this.isSaving = true;
    try {
      await saveResults({ ids, scores });
      this.toast(
        "저장했습니다",
        `결과 항목 ${ids.length}건 점수를 저장했습니다.`,
        "success"
      );
      // DESC: 판정 패널 · 기본 정보(getRecord)와 이 목록(Apex 캐시)을 모두 새로 읽는다
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      await refreshApex(this.wiredSheet);
      this.draftScoresById = {};
    } catch (error) {
      this.toast(
        "저장하지 못했습니다",
        reduceErrors(error).join(", "),
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  // DESC: 새로고침 서비스 · 상태 변경 공용 — 결과 시트(Apex 캐시)를 서버에서 다시 받는다. 새로고침 서비스는 Promise<boolean>을 기대한다
  refreshSheet() {
    if (!this.wiredSheet) {
      return Promise.resolve(true);
    }
    return refreshApex(this.wiredSheet).then(() => true);
  }

  currentScore(result) {
    return Object.prototype.hasOwnProperty.call(this.draftScoresById, result.id)
      ? this.draftScoresById[result.id]
      : this.normalize(result.score);
  }

  normalize(value) {
    return value === "" || value === null || value === undefined
      ? null
      : Number(value);
  }

  isBlank(value) {
    return value === null || value === undefined;
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
