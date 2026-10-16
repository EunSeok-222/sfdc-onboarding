/* ======================================================================================
 * @description : 점검 레코드 상세 화면 (record-form + 판정 패널 + 시정조치 목록 · 추가)
 * @layer       : LWC
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.13   Kai        Created     최초 작성
 *  2026.10.13   Kai        Updated     저장 성공/실패 Toast 추가
 *  2026.10.13   Kai        Updated     판정 패널(inspectionJudgementPanel) 자식 배치
 *  2026.10.13   Kai        Updated     D7 설계 초안(SC-02) 2단 배치 — 왼쪽 기본 정보 · 오른쪽 판정
 *  2026.10.14   Kai        Updated     시정조치 목록(@wire) · 조치 추가 폼 배치, created 이벤트로 목록 갱신
 *  2026.10.14   Kai        Updated     기본 정보 record-form 2단 표시(columns=2)
 * ======================================================================================
 *  @see         : docs/d7-lwc-handoff.md §4, correctiveActionForm.js, CorrectiveActionController.cls
 * ======================================================================================*/
import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import { reduceErrors } from "c/ldsUtils";
import getByInspection from "@salesforce/apex/CorrectiveActionController.getByInspection";

const REQUIRED_LABEL_PREFIX = "[필수] ";

const ACTION_COLUMNS = [
  {
    label: "시정번호",
    fieldName: "recordUrl",
    type: "url",
    typeAttributes: { label: { fieldName: "Name" }, target: "_self" }
  },
  { label: "미흡 항목", fieldName: "itemLabel", type: "text" },
  { label: "상태", fieldName: "Status__c", type: "text" },
  // NOTE: Date 필드는 'date-local' — 'date'로 쓰면 UTC로 해석돼 시간대에 따라 하루 밀릴 수 있다 (inspectionList와 같은 이유)
  { label: "시정 기한", fieldName: "DueDate__c", type: "date-local" }
];

export default class InspectionDetail extends LightningElement {
  @api recordId;

  actionColumns = ACTION_COLUMNS;
  // NOTE: @wire가 넘겨주는 결과 객체({ data, error }) 전체를 보관한다. refreshApex는 이 객체를 받아
  //       어느 wire를 다시 불러올지 찾는다. result.data만 저장해 넘기면 연결이 끊겨 갱신되지 않는다
  wiredActions;

  // DESC: datatable은 InspectionResult__r.ItemName__c 같은 관계 경로를 fieldName으로 못 읽으므로 1단 속성으로 평탄화한다
  //       (inspectionList.toRow와 같은 이유)
  get actionRows() {
    const actions = this.wiredActions?.data ?? [];
    return actions.map((action) => ({
      ...action,
      itemLabel: action.InspectionResult__r?.IsRequired__c
        ? REQUIRED_LABEL_PREFIX + action.InspectionResult__r.ItemName__c
        : action.InspectionResult__r?.ItemName__c,
      recordUrl: `/lightning/r/CorrectiveAction__c/${action.Id}/view`
    }));
  }

  get hasActions() {
    return this.actionRows.length > 0;
  }

  get isActionsLoaded() {
    return Boolean(this.wiredActions?.data || this.wiredActions?.error);
  }

  @wire(getByInspection, { inspectionId: "$recordId" })
  handleActionsWire(result) {
    this.wiredActions = result;
    if (result.error) {
      this.showErrorToast("시정조치를 불러오지 못했습니다", result.error);
    }
  }

  handleSuccess() {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "저장 완료",
        message: "점검 정보가 저장되었습니다.",
        variant: "success",
        mode: "dismissible"
      })
    );
  }

  handleError(event) {
    // NOTE: record-form의 onerror detail은 { message, output: { errors, fieldErrors } } 형태라
    //       body가 없다. reduceErrors는 error.body.output을 보므로 body로 감싸서 넘긴다.
    //       그대로 넘기면 detail.message(일반 문구)만 나오고 트리거 addError 문구가 빠진다.
    const messages = reduceErrors({ body: event.detail });
    this.dispatchEvent(
      new ShowToastEvent({
        title: "저장 실패",
        message: messages.join(", "),
        variant: "error",
        mode: "sticky"
      })
    );
  }

  // DESC: 자식(correctiveActionForm)이 조치 저장 후 발행한 created 이벤트를 받아 목록을 다시 불러온다
  // NOTE: 이 목록은 @wire로 받았으므로 refreshApex로 같은 wire를 서버에서 다시 받는다(cacheable 캐시도 갱신).
  //       목록 화면(inspectionList)은 imperative 호출이라 loadInspections()를 다시 불렀지만, wire에는 다시 부를 함수가 없다
  handleActionCreated() {
    return refreshApex(this.wiredActions);
  }

  showErrorToast(title, error) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message: reduceErrors(error).join(", "),
        variant: "error",
        mode: "sticky"
      })
    );
  }
}
