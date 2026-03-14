import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import autoFocus from "discourse/modifiers/auto-focus";
import { not } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * Modal for creating a standalone merch packet (not linked to a donation)
 *
 * @component CreateMerchPacketModal
 * @param {Function} model.onCreated - Callback when packet is created
 */
export default class CreateMerchPacketModal extends Component {
  @tracked packetTitle = "";
  @tracked donorName = "";
  @tracked donorCompany = "";
  @tracked donorStreet = "";
  @tracked donorStreetNumber = "";
  @tracked donorPostcode = "";
  @tracked donorCity = "";
  @tracked donorEmail = "";
  @tracked isSubmitting = false;

  /**
   * @type {boolean}
   */
  get canSubmit() {
    return (
      this.packetTitle.trim().length >= 3 &&
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
    return this.isSubmitting
      ? "vzekc_verlosung.merch_packets.create_modal.creating"
      : "vzekc_verlosung.merch_packets.create_modal.create";
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
  async submit() {
    if (this.isSubmitting || !this.canSubmit) {
      return;
    }

    this.isSubmitting = true;

    try {
      await ajax("/vzekc-verlosung/merch-packets", {
        type: "POST",
        data: {
          title: this.packetTitle.trim(),
          donor_name: this.donorName.trim(),
          donor_company: this.donorCompany.trim() || null,
          donor_street: this.donorStreet.trim(),
          donor_street_number: this.donorStreetNumber.trim(),
          donor_postcode: this.donorPostcode.trim(),
          donor_city: this.donorCity.trim(),
          donor_email: this.donorEmail.trim() || null,
        },
      });

      this.args.model.onCreated?.();
      this.args.closeModal();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSubmitting = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "vzekc_verlosung.merch_packets.create_modal.title"}}
      @closeModal={{@closeModal}}
      class="create-merch-packet-modal"
    >
      <:body>
        <form {{on "submit" this.preventSubmit}} class="merch-packet-form">
          <div class="control-group">
            <label>{{i18n
                "vzekc_verlosung.merch_packets.create_modal.packet_title_label"
              }}<span class="required">*</span></label>
            <input
              type="text"
              {{on "input" (fn this.updateField "packetTitle")}}
              {{on "keydown" this.handleKeyDown}}
              {{autoFocus}}
              value={{this.packetTitle}}
              placeholder={{i18n
                "vzekc_verlosung.merch_packets.create_modal.packet_title_placeholder"
              }}
              class="packet-title-input"
            />
          </div>

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
      </:footer>
    </DModal>
  </template>
}
