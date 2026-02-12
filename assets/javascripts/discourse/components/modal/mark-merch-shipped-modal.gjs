import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { i18n } from "discourse-i18n";

/**
 * Modal for marking a merch packet as shipped
 *
 * @component MarkMerchShippedModal
 * @param {Object} model.packet - The packet to mark as shipped
 * @param {Function} model.onConfirm - Callback when confirmed
 * @param {Function} model.onClose - Optional callback when modal closes
 */
export default class MarkMerchShippedModal extends Component {
  @tracked trackingInfo = "";
  @tracked isSubmitting = false;

  get packet() {
    return this.args.model.packet;
  }

  /**
   * Update tracking info field
   *
   * @param {Event} event - Input event
   */
  @action
  updateTrackingInfo(event) {
    this.trackingInfo = event.target.value;
  }

  /**
   * Close the modal and call onClose callback
   */
  @action
  handleClose() {
    this.args.model.onClose?.();
    this.args.closeModal();
  }

  /**
   * Confirm shipping the packet
   */
  @action
  async confirm() {
    this.isSubmitting = true;

    try {
      await this.args.model.onConfirm(this.packet, this.trackingInfo.trim());
      this.handleClose();
    } finally {
      this.isSubmitting = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "vzekc_verlosung.merch_packets.ship_modal.title"}}
      @closeModal={{this.handleClose}}
      class="mark-merch-shipped-modal"
    >
      <:body>
        <div class="ship-modal-content">
          <div class="packet-info">
            <h4>{{i18n
                "vzekc_verlosung.merch_packets.ship_modal.donation"
              }}</h4>
            <p>{{this.packet.donation.title}}</p>
          </div>

          <div class="donor-address">
            <h4>{{i18n
                "vzekc_verlosung.merch_packets.ship_modal.shipping_to"
              }}</h4>
            <pre>{{this.packet.formatted_address}}</pre>
          </div>

          {{#if this.packet.donor_email}}
            <div class="donor-email-info">
              <p class="email-notice">
                {{i18n "vzekc_verlosung.merch_packets.ship_modal.email_notice"}}
                <strong>{{this.packet.donor_email}}</strong>
              </p>
            </div>
          {{/if}}

          <div class="tracking-input">
            <label for="tracking-info">
              {{i18n "vzekc_verlosung.merch_packets.ship_modal.tracking_label"}}
            </label>
            <input
              id="tracking-info"
              type="text"
              value={{this.trackingInfo}}
              {{on "input" this.updateTrackingInfo}}
              placeholder={{i18n
                "vzekc_verlosung.merch_packets.ship_modal.tracking_placeholder"
              }}
              class="tracking-info-input"
            />
            <p class="help-text">
              {{i18n "vzekc_verlosung.merch_packets.ship_modal.tracking_help"}}
            </p>
          </div>
        </div>
      </:body>
      <:footer>
        <DButton
          @action={{this.confirm}}
          @label="vzekc_verlosung.merch_packets.ship_modal.confirm"
          @icon={{if this.isSubmitting "spinner" "truck"}}
          @disabled={{this.isSubmitting}}
          class="btn-primary"
        />
        <DButton
          @action={{this.handleClose}}
          @label="cancel"
          @disabled={{this.isSubmitting}}
          class="btn-default"
        />
      </:footer>
    </DModal>
  </template>
}
