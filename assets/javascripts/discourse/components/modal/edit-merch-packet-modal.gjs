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
import autoFocus from "discourse/modifiers/auto-focus";
import { not } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * Modal for editing or creating a merch packet for a donation
 *
 * @component EditMerchPacketModal
 * @param {Object} model.donation - The donation object
 * @param {Object} model.merch_packet - Existing merch packet data (null for create)
 * @param {Function} model.onSaved - Callback after save
 */
export default class EditMerchPacketModal extends Component {
  @service dialog;

  @tracked donorName = this.args.model.merch_packet?.donor_name || "";
  @tracked donorCompany = this.args.model.merch_packet?.donor_company || "";
  @tracked donorStreet = this.args.model.merch_packet?.donor_street || "";
  @tracked donorStreetNumber =
    this.args.model.merch_packet?.donor_street_number || "";
  @tracked donorPostcode = this.args.model.merch_packet?.donor_postcode || "";
  @tracked donorCity = this.args.model.merch_packet?.donor_city || "";
  @tracked donorEmail = this.args.model.merch_packet?.donor_email || "";
  @tracked isSubmitting = false;

  get isCreate() {
    return !this.args.model.merch_packet;
  }

  /**
   * @type {string}
   */
  get titleKey() {
    return this.isCreate
      ? "vzekc_verlosung.active_donations.merch_packet.create_title"
      : "vzekc_verlosung.active_donations.merch_packet.edit_title";
  }

  /**
   * @type {boolean}
   */
  get canSubmit() {
    return (
      this.donorName.trim().length >= 2 &&
      this.donorStreet.trim().length >= 2 &&
      this.donorStreetNumber.trim().length >= 1 &&
      this.donorPostcode.trim().length >= 4 &&
      this.donorCity.trim().length >= 2
    );
  }

  /**
   * @type {string}
   */
  get submitLabelKey() {
    if (this.isSubmitting) {
      return this.isCreate
        ? "vzekc_verlosung.donation_modal.creating"
        : "saving";
    }
    return this.isCreate
      ? "vzekc_verlosung.active_donations.merch_packet.create_button"
      : "save";
  }

  /**
   * @param {string} field
   * @param {Event} event
   */
  @action
  updateField(field, event) {
    this[field] = event.target.value;
  }

  /**
   * @param {KeyboardEvent} event
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
   * @param {Event} event
   */
  @action
  preventSubmit(event) {
    event.preventDefault();
    return false;
  }

  @action
  confirmDelete() {
    this.dialog.yesNoConfirm({
      message: i18n(
        "vzekc_verlosung.active_donations.merch_packet.delete_confirm"
      ),
      didConfirm: async () => {
        try {
          const donationId = this.args.model.donation.id;
          await ajax(`/vzekc-verlosung/donations/${donationId}/merch-packet`, {
            type: "DELETE",
          });
          this.args.model.onDeleted?.();
          this.args.closeModal();
        } catch (error) {
          popupAjaxError(error);
        }
      },
    });
  }

  @action
  async submit() {
    if (this.isSubmitting || !this.canSubmit) {
      return;
    }

    this.isSubmitting = true;
    const donationId = this.args.model.donation.id;

    try {
      const data = {
        donor_name: this.donorName.trim(),
        donor_company: this.donorCompany.trim() || null,
        donor_street: this.donorStreet.trim(),
        donor_street_number: this.donorStreetNumber.trim(),
        donor_postcode: this.donorPostcode.trim(),
        donor_city: this.donorCity.trim(),
        donor_email: this.donorEmail.trim() || null,
      };

      await ajax(`/vzekc-verlosung/donations/${donationId}/merch-packet`, {
        type: this.isCreate ? "POST" : "PUT",
        data,
      });

      this.args.model.onSaved?.();
      this.args.closeModal();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSubmitting = false;
    }
  }

  <template>
    <DModal
      @title={{i18n this.titleKey}}
      @closeModal={{@closeModal}}
      class="edit-merch-packet-modal"
    >
      <:body>
        <form {{on "submit" this.preventSubmit}} class="merch-packet-form">
          <fieldset class="donor-address-section">
            <div class="control-group">
              <label>{{i18n
                  "vzekc_verlosung.donation_modal.donor_name_label"
                }}<span class="required">*</span></label>
              <input
                type="text"
                {{on "input" (fn this.updateField "donorName")}}
                {{on "keydown" this.handleKeyDown}}
                {{autoFocus}}
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
        </form>
      </:body>
      <:footer>
        <DButton
          @action={{this.submit}}
          @label={{this.submitLabelKey}}
          @icon={{if this.isSubmitting "spinner" null}}
          @disabled={{not this.canSubmit}}
          class="btn-primary"
        />
        {{#unless this.isCreate}}
          <DButton
            @action={{this.confirmDelete}}
            @label="vzekc_verlosung.active_donations.merch_packet.delete"
            @icon="trash-can"
            class="btn-danger"
          />
        {{/unless}}
      </:footer>
    </DModal>
  </template>
}
