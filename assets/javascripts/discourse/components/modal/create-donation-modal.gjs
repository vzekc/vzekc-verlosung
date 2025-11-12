import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { not } from "truth-helpers";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import Composer from "discourse/models/composer";
import autoFocus from "discourse/modifiers/auto-focus";
import { i18n } from "discourse-i18n";

/**
 * Modal component for creating a new donation offer
 *
 * @component CreateDonationModal
 * Two-step process: collect title and postcode, then open composer
 */
export default class CreateDonationModal extends Component {
  @service composer;
  @service siteSettings;

  @tracked title = "";
  @tracked postcode = "";
  @tracked isSubmitting = false;

  /**
   * Check if user can submit
   *
   * @type {boolean}
   */
  get canSubmit() {
    return this.title.trim().length >= 3 && this.postcode.trim().length >= 3;
  }

  /**
   * Updates field value
   *
   * @param {string} field - Field name
   * @param {Event} event - Input event
   */
  @action
  updateField(field, event) {
    this[field] = event.target.value;
  }

  /**
   * Prevent Enter key from submitting forms
   *
   * @param {KeyboardEvent} event - Keyboard event
   */
  @action
  handleKeyDown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      event.stopPropagation();
      return false;
    }
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
      ? "vzekc_verlosung.donation_modal.creating"
      : "vzekc_verlosung.donation_modal.create";
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
   * Submit the donation creation and open composer
   */
  @action
  async submit() {
    if (this.isSubmitting || !this.canSubmit) {
      return;
    }

    this.isSubmitting = true;

    try {
      // Create draft donation
      const result = await ajax("/vzekc-verlosung/donations", {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify({
          postcode: this.postcode.trim(),
        }),
      });

      const donationId = result.donation_id;

      // Get the donation template and replace [POSTCODE]
      let template = this.siteSettings.vzekc_verlosung_donation_template || "";
      template = template.replace(/\[POSTCODE\]/g, this.postcode.trim());

      this.args.closeModal();

      // Open composer with pre-filled content and donation_id
      // Keys must match first parameter of serializeToDraft in donation-composer.js
      this.composer.open({
        action: Composer.CREATE_TOPIC,
        categoryId: this.args.model.categoryId,
        title: this.title.trim(),
        reply: template,
        draftKey: `new_topic_donation_${donationId}_${Date.now()}`,
        donation_id: donationId,
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSubmitting = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "vzekc_verlosung.donation_modal.title"}}
      @closeModal={{@closeModal}}
      class="create-donation-modal"
    >
      <:body>
        <form {{on "submit" this.preventSubmit}} class="donation-form">
          <div class="control-group">
            <label>{{i18n "vzekc_verlosung.donation_modal.title_label"}}</label>
            <input
              type="text"
              {{on "input" (fn this.updateField "title")}}
              {{on "keydown" this.handleKeyDown}}
              {{autoFocus}}
              value={{this.title}}
              placeholder={{i18n
                "vzekc_verlosung.donation_modal.title_placeholder"
              }}
              class="donation-title-input"
            />
          </div>

          <div class="control-group">
            <label>{{i18n
                "vzekc_verlosung.donation_modal.postcode_label"
              }}</label>
            <input
              type="text"
              {{on "input" (fn this.updateField "postcode")}}
              {{on "keydown" this.handleKeyDown}}
              value={{this.postcode}}
              placeholder={{i18n
                "vzekc_verlosung.donation_modal.postcode_placeholder"
              }}
              class="donation-postcode-input"
            />
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
