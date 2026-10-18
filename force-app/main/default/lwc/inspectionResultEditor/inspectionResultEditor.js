/* ======================================================================================
 * @description : 점검 결과 입력 (SC-02) — 분류별 결과 항목에 점수를 넣고 한 번에 저장한다. 미흡은 트리거가 판정(읽기 전용)
 * @layer       : LWC
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.18   Kai        Created     최초 작성 — 26-10-18 SC-02 점검 결과 입력
 *  2026.10.18   Kai        Updated     26-10-18 좁은 영역 세로 배치 by Kai
 * ======================================================================================
 *  @see         : InspectionResultController.cls, inspectionJudgementPanel(저장 뒤 getRecord로 갱신)
 *  @note        : 범위 밖 — 사진 첨부(BR-04) · 임시 저장/완료 분리 · 완료 미리보기 · 행 추가/삭제. 버튼은 「저장」 하나
 * ======================================================================================*/
import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { reduceErrors } from "c/ldsUtils";
import getResults from "@salesforce/apex/InspectionResultController.getResults";
import saveResults from "@salesforce/apex/InspectionResultController.saveResults";

export default class InspectionResultEditor extends LightningElement {
  @api recordId;
  // NOTE: 레코드 페이지가 넣어 주는 영역 폭(SMALL · MEDIUM · LARGE). App Page 등에서는 비어 있다
  @api flexipageRegionWidth;

  // DESC: 화면에서 고친 점수만 담는다 — 결과 항목 Id → 점수(비우면 null)
  draftScoresById = {};
  results = [];
  isReadOnly = true;
  isLoaded = false;
  isSaving = false;
  wiredSheet;

  @wire(getResults, { inspectionId: "$recordId" })
  wiredResults(value) {
    this.wiredSheet = value;
    const { data, error } = value;
    if (data) {
      this.results = data.results;
      this.isReadOnly = data.isReadOnly;
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

  get hasResults() {
    return this.results.length > 0;
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
      getRecordNotifyChange([{ recordId: this.recordId }]);
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
