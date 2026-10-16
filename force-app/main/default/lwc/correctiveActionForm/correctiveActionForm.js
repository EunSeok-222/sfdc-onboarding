/* ======================================================================================
 * @description : 점검의 미흡 결과 항목에 시정조치를 추가하는 폼 (점검 상세의 자식 컴포넌트)
 * @layer       : LWC
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.14   Kai        Created     최초 작성 (미흡 항목 선택 + record-edit-form 저장까지, 이벤트 없음)
 *  2026.10.14   Kai        Updated     저장 성공 시 created 이벤트 발행
 * ======================================================================================
 *  @see         : CorrectiveActionController.cls, inspectionDetail.js
 *  @note        : 저장 성공은 created 이벤트로 알리기만 한다. 목록 갱신은 받는 쪽(부모)이 정한다
 * ======================================================================================*/
import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { reduceErrors } from "c/ldsUtils";
import getDeficientResults from "@salesforce/apex/CorrectiveActionController.getDeficientResults";

const REQUIRED_LABEL_PREFIX = "[필수] ";

export default class CorrectiveActionForm extends LightningElement {
  targetInspectionId;
  deficientResults = [];
  selectedResultId;
  isLoaded = false;
  isSaving = false;
  _inspectionId;
  _recordId;

  // DESC: 부모(inspectionDetail)가 내려주는 점검 Id
  @api
  get inspectionId() {
    return this._inspectionId;
  }
  set inspectionId(value) {
    this._inspectionId = value;
    this.updateTargetInspectionId();
  }

  // NOTE: 이번 단계는 점검 레코드 페이지에 단독 배치해 저장을 확인한다. 그때는 부모가 없어 inspectionId가 비므로
  //       페이지가 넣어 주는 recordId로 대신한다. 부모가 inspection-id를 내려주면 그 값이 우선이다
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    this._recordId = value;
    this.updateTargetInspectionId();
  }

  // DESC: 콤보박스 선택지. 필수 항목은 [필수]를 붙여 BR-03(필수 미흡 = 불합격) 항목이 눈에 띄게 한다
  get resultOptions() {
    return this.deficientResults.map((result) => ({
      label: result.IsRequired__c
        ? REQUIRED_LABEL_PREFIX + result.ItemName__c
        : result.ItemName__c,
      value: result.Id
    }));
  }

  get hasDeficientResults() {
    return this.deficientResults.length > 0;
  }

  get isLoading() {
    return Boolean(this.targetInspectionId) && !this.isLoaded;
  }

  @wire(getDeficientResults, { inspectionId: "$targetInspectionId" })
  wiredDeficientResults({ data, error }) {
    if (data) {
      this.deficientResults = data;
      this.isLoaded = true;
    } else if (error) {
      this.deficientResults = [];
      this.isLoaded = true;
      this.showErrorToast(error);
    }
  }

  handleResultChange(event) {
    this.selectedResultId = event.detail.value;
  }

  // DESC: 콤보박스는 record-edit-form 밖의 일반 입력이라 폼 제출이 필수 여부를 검사하지 않는다 → 제출 전에 직접 검사한다
  handleSubmit(event) {
    event.preventDefault();
    const combobox = this.template.querySelector("lightning-combobox");
    if (!combobox.reportValidity()) {
      return;
    }
    // NOTE: 숨긴 결과 항목 필드에도 값이 바인딩되어 있지만, 제출 직전에 선택값을 한 번 더 넣어 어긋날 여지를 없앤다
    const fields = {
      ...event.detail.fields,
      InspectionResult__c: this.selectedResultId
    };
    this.isSaving = true;
    this.template.querySelector("lightning-record-edit-form").submit(fields);
  }

  handleSuccess(event) {
    this.isSaving = false;
    this.dispatchEvent(
      new ShowToastEvent({
        title: "조치 추가 완료",
        message: "시정조치가 저장되었습니다.",
        variant: "success",
        mode: "dismissible"
      })
    );
    // NOTE: 이벤트 이름은 전부 소문자 'created'. 부모는 on + 이름(oncreated)으로 받는데, 대문자(actionCreated)나
    //       하이픈(action-created)을 쓰면 에러 없이 조용히 안 잡힌다
    // NOTE: bubbles · composed를 주지 않는다(기본값 false · false). 받는 쪽이 이 컴포넌트를 직접 품은 부모 하나뿐이라
    //       위로 퍼뜨릴 이유가 없고, composed를 켜면 shadow 경계를 넘어 남의 컴포넌트까지 이벤트가 샌다
    // NOTE: inspectionId는 화면이 실제로 조회에 쓴 점검 Id(부모가 준 값, 없으면 페이지 recordId)를 싣는다
    this.dispatchEvent(
      new CustomEvent("created", {
        detail: {
          actionId: event.detail.id,
          inspectionId: this.targetInspectionId
        }
      })
    );
    this.resetForm();
  }

  handleError(event) {
    this.isSaving = false;
    // NOTE: record-form · record-edit-form의 onerror detail은 { message, output: { errors, fieldErrors } } 형태라
    //       body가 없다. reduceErrors는 error.body.output을 보므로 body로 감싸서 넘긴다.
    //       그대로 넘기면 detail.message(일반 문구)만 나오고 트리거 addError 문구가 빠진다.
    const messages = reduceErrors({ body: event.detail });
    this.dispatchEvent(
      new ShowToastEvent({
        title: "조치 추가 실패",
        message: messages.join(", "),
        variant: "error",
        mode: "sticky"
      })
    );
  }

  // DESC: 같은 점검에 조치를 이어서 추가할 수 있게 선택 항목과 입력값을 비운다
  resetForm() {
    this.selectedResultId = undefined;
    this.template
      .querySelectorAll("lightning-input-field")
      .forEach((field) => field.reset());
  }

  showErrorToast(error) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "미흡 항목을 불러오지 못했습니다",
        message: reduceErrors(error).join(", "),
        variant: "error",
        mode: "sticky"
      })
    );
  }

  updateTargetInspectionId() {
    const nextId = this._inspectionId || this._recordId;
    if (nextId !== this.targetInspectionId) {
      this.targetInspectionId = nextId;
      this.isLoaded = false;
    }
  }
}
