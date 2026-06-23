import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
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
 * Modal component for assigning a donation offer with contact information
 *
 * @component AssignOfferModal
 * Allows facilitator to provide donor's contact info when assigning offer to picker
 *
 * @param {Object} args.model.offer - The pickup offer to assign to the picker (manual mode only)
 * @param {number} args.model.donationId - The donation ID
 * @param {boolean} args.model.auto - When true, the server auto-selects the picker on submit
 * @param {boolean} args.model.requireExplanation - When true, the choice diverges from the fair pick and an explanation is required
 * @param {Array<string>} args.model.systemChoice - Usernames the system would have picked
 * @param {Function} args.model.onAssigned - Callback after successful assignment
 */
export default class AssignOfferModal extends Component {
  @tracked contactInfo = "";
  @tracked explanation = "";
  @tracked isSubmitting = false;

  /**
   * Whether this is an automatic assignment (server selects the recipient)
   *
   * @type {boolean}
   */
  get isAuto() {
    return this.args.model.auto === true;
  }

  /**
   * Whether the manual choice diverges from the fair pick and requires a reason
   *
   * @type {boolean}
   */
  get requireExplanation() {
    return this.args.model.requireExplanation === true;
  }

  /**
   * Usernames the system would have picked, as a German-style list
   * ("A und B" for two, "A, B und C" for three or more)
   *
   * @type {string}
   */
  get systemChoiceLabel() {
    const names = this.args.model.systemChoice || [];
    if (names.length <= 1) {
      return names.join("");
    }
    const head = names.slice(0, -1);
    const tail = names[names.length - 1];
    const and = i18n("vzekc_verlosung.assign_offer_modal.and");
    return `${head.join(", ")} ${and} ${tail}`;
  }

  /**
   * Help-text key: a single lowest-count picker would have been assigned
   * directly; a tie would have been drawn by lot.
   *
   * @type {string}
   */
  get explanationHelpKey() {
    const count = (this.args.model.systemChoice || []).length;
    return count <= 1
      ? "vzekc_verlosung.assign_offer_modal.explanation_help_one"
      : "vzekc_verlosung.assign_offer_modal.explanation_help_many";
  }

  /**
   * The modal title key, depending on the assignment mode
   *
   * @type {string}
   */
  get titleKey() {
    return this.isAuto
      ? "vzekc_verlosung.assign_offer_modal.auto_title"
      : "vzekc_verlosung.assign_offer_modal.title";
  }

  /**
   * Check if user can submit
   *
   * @type {boolean}
   */
  get canSubmit() {
    if (this.contactInfo.trim().length < 10) {
      return false;
    }
    if (this.requireExplanation && this.explanation.trim().length === 0) {
      return false;
    }
    return true;
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
   * Updates explanation field
   *
   * @param {Event} event - Input event
   */
  @action
  updateExplanation(event) {
    this.explanation = event.target.value;
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
    if (this.isSubmitting) {
      return "vzekc_verlosung.assign_offer_modal.assigning";
    }
    return this.isAuto
      ? "vzekc_verlosung.assign_offer_modal.auto_assign"
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

    const url = this.isAuto
      ? `/vzekc-verlosung/donations/${this.args.model.donationId}/auto-assign`
      : `/vzekc-verlosung/pickup-offers/${this.args.model.offer.id}/assign`;

    try {
      await ajax(url, {
        type: "PUT",
        contentType: "application/json",
        data: JSON.stringify({
          contact_info: this.contactInfo.trim(),
          explanation: this.explanation.trim(),
        }),
      });

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
      @title={{i18n this.titleKey}}
      @closeModal={{@closeModal}}
      class="assign-offer-modal"
    >
      <:body>
        <form {{on "submit" this.preventSubmit}} class="assign-offer-form">
          {{#if this.isAuto}}
            <div class="assign-offer-auto-description">
              {{i18n "vzekc_verlosung.assign_offer_modal.auto_description"}}
            </div>
          {{else}}
            <div class="assign-offer-user">
              <strong>{{i18n
                  "vzekc_verlosung.assign_offer_modal.assigning_to"
                }}:</strong>
              {{@model.offer.user.username}}
            </div>
          {{/if}}

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

          {{#if this.requireExplanation}}
            <div class="control-group assign-offer-explanation">
              <label>{{i18n
                  "vzekc_verlosung.assign_offer_modal.explanation_label"
                }}</label>
              <textarea
                {{on "input" this.updateExplanation}}
                value={{this.explanation}}
                placeholder={{i18n
                  "vzekc_verlosung.assign_offer_modal.explanation_placeholder"
                }}
                class="explanation-input"
                rows="4"
              ></textarea>
              <div class="explanation-help">
                {{i18n
                  this.explanationHelpKey
                  candidates=this.systemChoiceLabel
                  picker=@model.offer.user.username
                }}
              </div>
            </div>
          {{/if}}
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
