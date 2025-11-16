import Component from "@glimmer/component";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * Modal component for confirming lottery creation details
 *
 * @component ConfirmLotteryModal
 * Shows a formatted review of lottery details before creation
 *
 * @param {Object} model.lotteryData - The lottery data to confirm
 * @param {Function} model.onConfirm - Callback when user confirms
 */
export default class ConfirmLotteryModal extends Component {
  /**
   * Get the lottery data from model
   *
   * @type {Object}
   */
  get lotteryData() {
    return this.args.model.lotteryData;
  }

  /**
   * Get the drawing mode text
   *
   * @type {string}
   */
  get drawingModeText() {
    return this.lotteryData.drawingMode === "automatic"
      ? i18n("vzekc_verlosung.modal.drawing_mode_automatic")
      : i18n("vzekc_verlosung.modal.drawing_mode_manual");
  }

  /**
   * Get packet number for display (1-indexed)
   *
   * @param {number} index - Zero-based index
   * @returns {number} One-based packet number
   */
  getPacketNumber(index) {
    return index + 1;
  }

  /**
   * Go back to editing
   */
  @action
  goBack() {
    this.args.closeModal();
    if (this.args.model.onBack) {
      this.args.model.onBack();
    }
  }

  /**
   * Confirm and create the lottery
   */
  @action
  confirm() {
    this.args.closeModal();
    if (this.args.model.onConfirm) {
      this.args.model.onConfirm();
    }
  }

  <template>
    <DModal
      @title={{i18n "vzekc_verlosung.modal.confirm_title"}}
      @closeModal={{@closeModal}}
      class="confirm-lottery-modal"
    >
      <:body>
        <div class="lottery-confirmation">
          <p class="confirmation-help">{{i18n
              "vzekc_verlosung.modal.confirm_review"
            }}</p>

          <div class="confirmation-details">
            <div class="detail-row">
              <span class="detail-label">{{i18n
                  "vzekc_verlosung.modal.title_label"
                }}:</span>
              <span class="detail-value">{{this.lotteryData.title}}</span>
            </div>

            <div class="detail-row">
              <span class="detail-label">{{i18n
                  "vzekc_verlosung.modal.duration_label"
                }}:</span>
              <span class="detail-value">{{this.lotteryData.durationDays}}
                {{i18n "vzekc_verlosung.modal.days"}}</span>
            </div>

            <div class="detail-row">
              <span class="detail-label">{{i18n
                  "vzekc_verlosung.modal.drawing_mode_label"
                }}:</span>
              <span class="detail-value">{{this.drawingModeText}}</span>
            </div>
          </div>

          <h4>{{i18n "vzekc_verlosung.modal.packets_label"}}</h4>

          <div class="confirmation-packets">
            {{#unless this.lotteryData.noAbholerpaket}}
              <div class="packet-row abholerpaket">
                <span class="packet-badge">{{i18n
                    "vzekc_verlosung.modal.abholerpaket_badge"
                  }}</span>
                <span
                  class="packet-title"
                >{{this.lotteryData.abholerpaketTitle}}</span>
                {{#if this.lotteryData.abholerpaketErhaltungsberichtRequired}}
                  <span class="packet-meta">
                    {{icon "file-lines"}}
                    {{i18n
                      "vzekc_verlosung.modal.erhaltungsbericht_required_short"
                    }}
                  </span>
                {{/if}}
              </div>
            {{/unless}}

            {{#each this.lotteryData.packets as |packet index|}}
              <div class="packet-row">
                <span class="packet-badge">{{i18n
                    "vzekc_verlosung.modal.packet_badge"
                    number=(this.getPacketNumber index)
                  }}</span>
                <span class="packet-title">{{packet.title}}</span>
                {{#if packet.erhaltungsberichtRequired}}
                  <span class="packet-meta">
                    {{icon "file-lines"}}
                    {{i18n
                      "vzekc_verlosung.modal.erhaltungsbericht_required_short"
                    }}
                  </span>
                {{/if}}
              </div>
            {{/each}}
          </div>
        </div>
      </:body>

      <:footer>
        <DButton
          @action={{this.goBack}}
          @label="vzekc_verlosung.modal.back_to_edit"
          class="btn-default"
        />
        <DButton
          @action={{this.confirm}}
          @label="vzekc_verlosung.modal.create"
          @icon="check"
          class="btn-primary"
        />
      </:footer>
    </DModal>
  </template>
}
