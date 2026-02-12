import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import Composer from "discourse/models/composer";
import autoFocus from "discourse/modifiers/auto-focus";
import { not } from "discourse/truth-helpers";
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

  @tracked skipMerchPacket = false;
  @tracked donorName = "";
  @tracked donorCompany = "";
  @tracked donorStreet = "";
  @tracked donorStreetNumber = "";
  @tracked donorPostcode = "";
  @tracked donorCity = "";
  @tracked donorEmail = "";

  /**
   * Check if user can submit
   *
   * @type {boolean}
   */
  get canSubmit() {
    const basicValid =
      this.title.trim().length >= 3 && this.postcode.trim().length >= 3;

    if (!basicValid) {
      return false;
    }

    // If merch packet is NOT skipped, require address fields
    if (!this.skipMerchPacket) {
      return (
        this.donorName.trim().length >= 2 &&
        this.donorStreet.trim().length >= 2 &&
        this.donorStreetNumber.trim().length >= 1 &&
        this.donorPostcode.trim().length >= 4 &&
        this.donorCity.trim().length >= 2
      );
    }

    return true;
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
   * Toggle skip merch packet checkbox
   */
  @action
  toggleSkipMerchPacket() {
    this.skipMerchPacket = !this.skipMerchPacket;
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
      const requestData = {
        postcode: this.postcode.trim(),
      };

      // Send merch packet data unless explicitly skipped
      if (!this.skipMerchPacket) {
        requestData.donor_name = this.donorName.trim();
        requestData.donor_company = this.donorCompany.trim() || null;
        requestData.donor_street = this.donorStreet.trim();
        requestData.donor_street_number = this.donorStreetNumber.trim();
        requestData.donor_postcode = this.donorPostcode.trim();
        requestData.donor_city = this.donorCity.trim();
        requestData.donor_email = this.donorEmail.trim() || null;
      }

      const result = await ajax("/vzekc-verlosung/donations", {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify(requestData),
      });

      const donationId = result.donation_id;

      let template = this.siteSettings.vzekc_verlosung_donation_template || "";
      template = template.replace(/\[POSTCODE\]/g, this.postcode.trim());

      this.args.closeModal();

      const topicTitle = `${this.title.trim()} in ${this.postcode.trim()}`;

      this.composer.open({
        action: Composer.CREATE_TOPIC,
        categoryId: this.args.model.categoryId,
        title: topicTitle,
        reply: template,
        draftKey: `new_topic_donation_${donationId}_${Date.now()}`,
        donation_id: donationId,
        skipSimilarTopics: true,
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

          <div class="control-group merch-packet-section">
            <label class="checkbox-label">
              <input
                type="checkbox"
                checked={{this.skipMerchPacket}}
                {{on "change" this.toggleSkipMerchPacket}}
              />
              {{i18n "vzekc_verlosung.donation_modal.skip_merch_packet"}}
            </label>
            {{#unless this.skipMerchPacket}}
              <p class="help-text">{{i18n
                  "vzekc_verlosung.donation_modal.merch_packet_help"
                }}</p>
            {{/unless}}
          </div>

          {{#unless this.skipMerchPacket}}
            <fieldset class="donor-address-section">
              <div class="control-group">
                <label>{{i18n
                    "vzekc_verlosung.donation_modal.donor_name_label"
                  }}<span class="required">*</span></label>
                <input
                  type="text"
                  {{on "input" (fn this.updateField "donorName")}}
                  {{on "keydown" this.handleKeyDown}}
                  value={{this.donorName}}
                  placeholder={{i18n
                    "vzekc_verlosung.donation_modal.donor_name_placeholder"
                  }}
                  class="donor-name-input"
                />
              </div>

              <div class="control-group">
                <label>{{i18n
                    "vzekc_verlosung.donation_modal.donor_company_label"
                  }}</label>
                <input
                  type="text"
                  {{on "input" (fn this.updateField "donorCompany")}}
                  {{on "keydown" this.handleKeyDown}}
                  value={{this.donorCompany}}
                  placeholder={{i18n
                    "vzekc_verlosung.donation_modal.donor_company_placeholder"
                  }}
                  class="donor-company-input"
                />
              </div>

              <div class="control-group street-row">
                <div class="street-field">
                  <label>{{i18n
                      "vzekc_verlosung.donation_modal.donor_street_label"
                    }}<span class="required">*</span></label>
                  <input
                    type="text"
                    {{on "input" (fn this.updateField "donorStreet")}}
                    {{on "keydown" this.handleKeyDown}}
                    value={{this.donorStreet}}
                    placeholder={{i18n
                      "vzekc_verlosung.donation_modal.donor_street_placeholder"
                    }}
                    class="donor-street-input"
                  />
                </div>
                <div class="street-number-field">
                  <label>{{i18n
                      "vzekc_verlosung.donation_modal.donor_street_number_label"
                    }}<span class="required">*</span></label>
                  <input
                    type="text"
                    {{on "input" (fn this.updateField "donorStreetNumber")}}
                    {{on "keydown" this.handleKeyDown}}
                    value={{this.donorStreetNumber}}
                    placeholder={{i18n
                      "vzekc_verlosung.donation_modal.donor_street_number_placeholder"
                    }}
                    class="donor-street-number-input"
                  />
                </div>
              </div>

              <div class="control-group postal-row">
                <div class="postcode-field">
                  <label>{{i18n
                      "vzekc_verlosung.donation_modal.donor_postcode_label"
                    }}<span class="required">*</span></label>
                  <input
                    type="text"
                    {{on "input" (fn this.updateField "donorPostcode")}}
                    {{on "keydown" this.handleKeyDown}}
                    value={{this.donorPostcode}}
                    placeholder={{i18n
                      "vzekc_verlosung.donation_modal.donor_postcode_placeholder"
                    }}
                    class="donor-postcode-input"
                  />
                </div>
                <div class="city-field">
                  <label>{{i18n
                      "vzekc_verlosung.donation_modal.donor_city_label"
                    }}<span class="required">*</span></label>
                  <input
                    type="text"
                    {{on "input" (fn this.updateField "donorCity")}}
                    {{on "keydown" this.handleKeyDown}}
                    value={{this.donorCity}}
                    placeholder={{i18n
                      "vzekc_verlosung.donation_modal.donor_city_placeholder"
                    }}
                    class="donor-city-input"
                  />
                </div>
              </div>

              <div class="control-group">
                <label>{{i18n
                    "vzekc_verlosung.donation_modal.donor_email_label"
                  }}</label>
                <input
                  type="email"
                  name="email"
                  autocomplete="email"
                  {{on "input" (fn this.updateField "donorEmail")}}
                  {{on "keydown" this.handleKeyDown}}
                  value={{this.donorEmail}}
                  placeholder={{i18n
                    "vzekc_verlosung.donation_modal.donor_email_placeholder"
                  }}
                  class="donor-email-input"
                />
                <p class="help-text">{{i18n
                    "vzekc_verlosung.donation_modal.donor_email_help"
                  }}</p>
              </div>
            </fieldset>
          {{/unless}}
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
