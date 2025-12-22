import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { i18n } from "discourse-i18n";

/**
 * Modal component for marking a packet as shipped with optional tracking info
 *
 * @component MarkShippedModal
 * @param {Object} model.winnerUsername - Winner's username
 * @param {string} model.packetTitle - Packet title
 * @param {Function} model.onConfirm - Callback with tracking info
 */
export default class MarkShippedModal extends Component {
  @tracked trackingInfo = "";

  @action
  updateTrackingInfo(event) {
    this.trackingInfo = event.target.value;
  }

  @action
  confirm() {
    this.args.model.onConfirm(this.trackingInfo);
    this.args.closeModal();
  }

  <template>
    <DModal
      @title={{i18n "vzekc_verlosung.shipping.confirm_title"}}
      @closeModal={{@closeModal}}
      class="mark-shipped-modal"
    >
      <:body>
        <p>{{i18n
            "vzekc_verlosung.shipping.confirm_message"
            winner=@model.winnerUsername
            packet=@model.packetTitle
          }}</p>
        <div class="control-group tracking-info-field">
          <label>{{i18n "vzekc_verlosung.shipping.tracking_info_label"}}</label>
          <input
            type="text"
            {{on "input" this.updateTrackingInfo}}
            value={{this.trackingInfo}}
            placeholder={{i18n
              "vzekc_verlosung.shipping.tracking_info_placeholder"
            }}
            class="tracking-info-input"
          />
        </div>
      </:body>
      <:footer>
        <DButton
          @action={{this.confirm}}
          @label="vzekc_verlosung.shipping.shipped"
          @icon="paper-plane"
          class="btn-primary"
        />
      </:footer>
    </DModal>
  </template>
}
