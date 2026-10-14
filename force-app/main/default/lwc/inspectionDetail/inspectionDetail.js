/* ======================================================================================
 * @description : 점검 레코드 상세 화면 (record-form + 판정 패널)
 * @layer       : LWC
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.13   Kai        Created     최초 작성
 *  2026.10.13   Kai        Updated     저장 성공/실패 Toast 추가
 *  2026.10.13   Kai        Updated     판정 패널(inspectionJudgementPanel) 자식 배치
 *  2026.10.13   Kai        Updated     D7 설계 초안(SC-02) 2단 배치 — 왼쪽 기본 정보 · 오른쪽 판정
 * ======================================================================================
 *  @see         : docs/d7-lwc-handoff.md §4
 * ======================================================================================*/
import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { reduceErrors } from "c/ldsUtils";

export default class InspectionDetail extends LightningElement {
  @api recordId;

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
}
