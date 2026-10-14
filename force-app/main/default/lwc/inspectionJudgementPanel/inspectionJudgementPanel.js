/* ======================================================================================
 * @description : 점검 판정 패널 (총점/배점 · 달성률 바 · 판정 배지 · 필수 미흡 건수, 읽기 전용)
 * @layer       : LWC
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.13   Kai        Created     최초 작성
 *  2026.10.13   Kai        Updated     D7 설계 초안(Claude Design SC-02) 디자인 · SLDS 색 적용, BR-03 경고 추가
 * ======================================================================================
 *  @see         : docs/d7-lwc-handoff.md §4, InspectionService.cls (판정 계산)
 * ======================================================================================*/
import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { reduceErrors } from "c/ldsUtils";
import TOTAL_SCORE_FIELD from "@salesforce/schema/Inspection__c.ruTotalScore__c";
import MAX_SCORE_FIELD from "@salesforce/schema/Inspection__c.ruMaxScore__c";
import DEFICIENT_REQUIRED_COUNT_FIELD from "@salesforce/schema/Inspection__c.ruDeficientRequiredCount__c";
import JUDGEMENT_FIELD from "@salesforce/schema/Inspection__c.Judgement__c";

const FIELDS = [
  TOTAL_SCORE_FIELD,
  MAX_SCORE_FIELD,
  DEFICIENT_REQUIRED_COUNT_FIELD,
  JUDGEMENT_FIELD
];

// NOTE: InspectionRule__mdt.Default.PassRate__c(0.8)와 같은 값. LDS는 Custom Metadata를 읽지 못해 표시용 상수로 둔다
//       판정 자체는 서버(InspectionService)가 하므로 이 값은 바의 합격선 표시에만 쓴다
// TODO: 기준값이 바뀌면 화면과 어긋난다 — Apex로 기준값을 받아 상수 제거 (D8 이후)
const PASS_RATE_PERCENT = 80;

const MODIFIER_BY_JUDGEMENT = {
  합격: "pass",
  "시정 필요": "correction",
  불합격: "fail"
};

export default class InspectionJudgementPanel extends LightningElement {
  @api recordId;

  inspection;
  errorMessage;
  passRatePercent = PASS_RATE_PERCENT;

  get totalScore() {
    return this.getValue(TOTAL_SCORE_FIELD) ?? 0;
  }

  get maxScore() {
    return this.getValue(MAX_SCORE_FIELD) ?? 0;
  }

  get deficientRequiredCount() {
    return this.getValue(DEFICIENT_REQUIRED_COUNT_FIELD) ?? 0;
  }

  get judgement() {
    return this.getValue(JUDGEMENT_FIELD);
  }

  get hasResults() {
    return this.maxScore > 0;
  }

  get achievementRate() {
    return this.hasResults
      ? Math.round((this.totalScore / this.maxScore) * 100)
      : 0;
  }

  get judgementLabel() {
    return this.judgement ?? "판정 전";
  }

  get judgementModifier() {
    return MODIFIER_BY_JUDGEMENT[this.judgement] ?? "none";
  }

  get badgeClass() {
    return `wsds-judgement-panel__badge wsds-judgement-panel__badge--${this.judgementModifier}`;
  }

  // DESC: BR-03 — 필수 항목이 하나라도 미흡이면 총점과 무관하게 불합격. 화면은 알려만 주고 판정은 서버가 한다
  get hasDeficientRequired() {
    return this.deficientRequiredCount > 0;
  }

  get barFillClass() {
    return `wsds-judgement-panel__fill wsds-judgement-panel__fill--${this.judgementModifier}`;
  }

  get barFillStyle() {
    return `width: ${Math.min(this.achievementRate, 100)}%`;
  }

  get markerStyle() {
    return `left: ${PASS_RATE_PERCENT}%`;
  }

  get deficientValueClass() {
    return this.hasDeficientRequired
      ? "wsds-judgement-panel__value wsds-judgement-panel__value--alert"
      : "wsds-judgement-panel__value";
  }

  // NOTE: record-form 저장 시 LDS 캐시가 갱신되므로 별도 refresh 없이 판정이 다시 그려진다
  @wire(getRecord, { recordId: "$recordId", fields: FIELDS })
  wiredInspection({ data, error }) {
    if (data) {
      this.inspection = data;
      this.errorMessage = undefined;
    } else if (error) {
      this.inspection = undefined;
      this.errorMessage = reduceErrors(error).join(", ");
    }
  }

  getValue(field) {
    return this.inspection ? getFieldValue(this.inspection, field) : undefined;
  }
}
