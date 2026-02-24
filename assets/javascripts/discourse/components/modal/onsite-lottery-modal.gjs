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
 * Modal for assigning a donation to an onsite lottery event
 *
 * @component OnsiteLotteryModal
 * @param {number} args.model.donationId - The donation ID
 * @param {Function} args.model.onAssigned - Callback after successful assignment
 */
export default class OnsiteLotteryModal extends Component {
  @tracked isLoading = true;
  @tracked isSubmitting = false;
  @tracked existingEvent = null;
  @tracked eventName = "";
  @tracked eventDate = "";

  constructor() {
    super(...arguments);
    this.loadCurrentEvent();
  }

  /**
   * Load the current onsite lottery event
   */
  async loadCurrentEvent() {
    try {
      const result = await ajax(
        "/vzekc-verlosung/onsite-lottery-events/current"
      );
      this.existingEvent = result.event;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * Whether user can submit (existing event or valid new event data)
   *
   * @type {boolean}
   */
  get canSubmit() {
    if (this.isSubmitting || this.isLoading) {
      return false;
    }
    if (this.existingEvent) {
      return true;
    }
    return this.eventName.trim().length > 0 && this.eventDate.length > 0;
  }

  /**
   * Updates event name field
   *
   * @param {Event} event - Input event
   */
  @action
  updateEventName(event) {
    this.eventName = event.target.value;
  }

  /**
   * Updates event date field
   *
   * @param {Event} event - Input event
   */
  @action
  updateEventDate(event) {
    this.eventDate = event.target.value;
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
   * Format a date string for display
   *
   * @param {string} dateStr - ISO date string
   * @returns {string} Formatted date
   */
  formatDate(dateStr) {
    if (!dateStr) {
      return "";
    }
    const date = new Date(dateStr + "T00:00:00");
    return date.toLocaleDateString("de-DE", {
      day: "numeric",
      month: "long",
      year: "numeric",
    });
  }

  /**
   * Submit the assignment
   */
  @action
  async submit() {
    if (this.isSubmitting || !this.canSubmit) {
      return;
    }

    this.isSubmitting = true;

    try {
      const data = {};
      if (this.existingEvent) {
        data.event_id = this.existingEvent.id;
      } else {
        data.event_name = this.eventName.trim();
        data.event_date = this.eventDate;
      }

      await ajax(
        `/vzekc-verlosung/donations/${this.args.model.donationId}/assign-onsite-lottery`,
        {
          type: "POST",
          contentType: "application/json",
          data: JSON.stringify(data),
        }
      );

      this.args.closeModal();

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
      @title={{i18n "vzekc_verlosung.onsite_lottery.modal_title"}}
      @closeModal={{@closeModal}}
      class="onsite-lottery-modal"
    >
      <:body>
        {{#if this.isLoading}}
          <div class="onsite-lottery-loading">
            {{i18n "vzekc_verlosung.ticket.loading"}}
          </div>
        {{else}}
          <form {{on "submit" this.preventSubmit}} class="onsite-lottery-form">
            {{#if this.existingEvent}}
              <div class="existing-event-info">
                <p>{{i18n
                    "vzekc_verlosung.onsite_lottery.existing_event_description"
                  }}</p>
                <div class="event-details">
                  <div class="event-detail">
                    <strong>{{i18n
                        "vzekc_verlosung.onsite_lottery.event_name_label"
                      }}:</strong>
                    {{this.existingEvent.name}}
                  </div>
                  <div class="event-detail">
                    <strong>{{i18n
                        "vzekc_verlosung.onsite_lottery.event_date_label"
                      }}:</strong>
                    {{this.formatDate this.existingEvent.event_date}}
                  </div>
                  {{#if this.existingEvent.donations_count}}
                    <div class="event-detail">
                      <strong>{{i18n
                          "vzekc_verlosung.onsite_lottery.donations_count"
                          count=this.existingEvent.donations_count
                        }}</strong>
                    </div>
                  {{/if}}
                </div>
              </div>
            {{else}}
              <div class="create-event-info">
                <p>{{i18n
                    "vzekc_verlosung.onsite_lottery.create_event_description"
                  }}</p>
                <div class="control-group">
                  <label>{{i18n
                      "vzekc_verlosung.onsite_lottery.event_name_label"
                    }}</label>
                  <input
                    type="text"
                    {{on "input" this.updateEventName}}
                    {{autoFocus}}
                    value={{this.eventName}}
                    placeholder={{i18n
                      "vzekc_verlosung.onsite_lottery.event_name_placeholder"
                    }}
                    class="event-name-input"
                  />
                </div>
                <div class="control-group">
                  <label>{{i18n
                      "vzekc_verlosung.onsite_lottery.event_date_label"
                    }}</label>
                  <input
                    type="date"
                    {{on "input" this.updateEventDate}}
                    value={{this.eventDate}}
                    class="event-date-input"
                  />
                </div>
              </div>
            {{/if}}
          </form>
        {{/if}}
      </:body>
      <:footer>
        {{#if this.existingEvent}}
          <DButton
            @action={{this.submit}}
            @label={{if
              this.isSubmitting
              "vzekc_verlosung.onsite_lottery.creating"
              "vzekc_verlosung.onsite_lottery.confirm_button"
            }}
            @disabled={{(not this.canSubmit)}}
            class="btn-primary"
          />
        {{else}}
          <DButton
            @action={{this.submit}}
            @label={{if
              this.isSubmitting
              "vzekc_verlosung.onsite_lottery.creating"
              "vzekc_verlosung.onsite_lottery.create_and_confirm_button"
            }}
            @disabled={{(not this.canSubmit)}}
            class="btn-primary"
          />
        {{/if}}
      </:footer>
    </DModal>
  </template>
}
