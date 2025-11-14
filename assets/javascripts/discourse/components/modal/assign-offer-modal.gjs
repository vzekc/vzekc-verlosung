import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { not } from "truth-helpers";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import autoFocus from "discourse/modifiers/auto-focus";
import { i18n } from "discourse-i18n";

/**
 * Modal component for assigning a donation offer with contact information
 *
 * @component AssignOfferModal
 * Allows donation creator to provide donor's contact info when assigning an offer
 *
 * @param {Object} args.model.offer - The pickup offer to assign
 * @param {number} args.model.donationId - The donation ID
 * @param {Function} args.model.onAssigned - Callback after successful assignment
 */
export default class AssignOfferModal extends Component {
  @tracked contactInfo = "";
  @tracked isSubmitting = false;

  /**
   * Check if user can submit
   *
   * @type {boolean}
   */
  get canSubmit() {
    return this.contactInfo.trim().length >= 10;
  }

  /**
   * Updates contact info field
   *
   * @param {Event} event - Input event
   */
  @action
  updateContactInfo(event) {
    this.contactInfo = event.target.value;
  }

  /**
   * Prevent form submission
   *
   * @param {Event} event - Submit event
   */
  @action
  preventSubmit(event) {
    event.preventDefault();
    return false;
  }

  /**
   * Get the submit button label key
   *
   * @type {string}
   */
  get submitLabelKey() {
    return this.isSubmitting
      ? "vzekc_verlosung.assign_offer_modal.assigning"
      : "vzekc_verlosung.assign_offer_modal.assign";
  }

  /**
   * Get the submit button icon
   *
   * @type {string}
   */
  get submitIcon() {
    return this.isSubmitting ? "spinner" : null;
  }

  /**
   * Submit the assignment with contact info
   */
  @action
  async submit() {
    if (this.isSubmitting || !this.canSubmit) {
      return;
    }

    this.isSubmitting = true;

    try {
      await ajax(
        `/vzekc-verlosung/pickup-offers/${this.args.model.offer.id}/assign`,
        {
          type: "PUT",
          contentType: "application/json",
          data: JSON.stringify({
            contact_info: this.contactInfo.trim(),
          }),
        }
      );

      this.args.closeModal();

      // Notify the widget to refresh
      if (this.args.model.onAssigned) {
        this.args.model.onAssigned();
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSubmitting = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "vzekc_verlosung.assign_offer_modal.title"}}
      @closeModal={{@closeModal}}
      class="assign-offer-modal"
    >
      <:body>
        <form {{on "submit" this.preventSubmit}} class="assign-offer-form">
          <div class="assign-offer-user">
            <strong>{{i18n
                "vzekc_verlosung.assign_offer_modal.assigning_to"
              }}:</strong>
            {{@model.offer.user.username}}
          </div>

          <div class="control-group">
            <label>{{i18n
                "vzekc_verlosung.assign_offer_modal.contact_info_label"
              }}</label>
            <textarea
              {{on "input" this.updateContactInfo}}
              {{autoFocus}}
              value={{this.contactInfo}}
              placeholder={{i18n
                "vzekc_verlosung.assign_offer_modal.contact_info_placeholder"
              }}
              class="contact-info-input"
              rows="6"
            ></textarea>
            <div class="contact-info-help">
              {{i18n "vzekc_verlosung.assign_offer_modal.contact_info_help"}}
            </div>
          </div>
        </form>
      </:body>
      <:footer>
        <DButton
          @action={{this.submit}}
          @label={{this.submitLabelKey}}
          @icon={{this.submitIcon}}
          @disabled={{not this.canSubmit}}
          class="btn-primary"
        />
      </:footer>
    </DModal>
  </template>
}
