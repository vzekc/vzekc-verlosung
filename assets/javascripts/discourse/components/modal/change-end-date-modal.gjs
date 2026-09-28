import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

/**
 * Formats a date as the local-time value of a datetime-local input
 *
 * @param {Date} date - The date to format
 * @returns {String} Value in the form YYYY-MM-DDTHH:mm
 */
function toLocalInputValue(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}`
  );
}

/**
 * Staff modal for moving the deadline of an active lottery
 *
 * @component ChangeEndDateModal
 * @param {Number} model.topicId - Topic ID of the lottery
 * @param {String} model.endsAt - Current deadline as ISO 8601 timestamp
 */
export default class ChangeEndDateModal extends Component {
  @tracked value = toLocalInputValue(new Date(this.args.model.endsAt));
  @tracked submitting = false;

  /**
   * Earliest selectable deadline
   *
   * @returns {String} The current local time as datetime-local value
   */
  get minValue() {
    return toLocalInputValue(new Date());
  }

  /**
   * Whether the entered deadline is valid and in the future
   *
   * @returns {Boolean}
   */
  get isValid() {
    const date = new Date(this.value);
    return !isNaN(date.getTime()) && date > new Date();
  }

  /**
   * Whether the confirm button is disabled
   *
   * @returns {Boolean}
   */
  get isDisabled() {
    return this.submitting || !this.isValid;
  }

  /**
   * Stores the value entered in the date input
   *
   * @param {Event} event - The input event
   */
  @action
  updateValue(event) {
    this.value = event.target.value;
  }

  /**
   * Saves the new deadline and reloads the page
   */
  @action
  async confirm() {
    this.submitting = true;
    try {
      await ajax(
        `/vzekc-verlosung/lotteries/${this.args.model.topicId}/end-date`,
        {
          type: "PUT",
          data: { ends_at: new Date(this.value).toISOString() },
        }
      );
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
      this.submitting = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "vzekc_verlosung.change_end_date.modal_title"}}
      @closeModal={{@closeModal}}
      class="change-end-date-modal"
    >
      <:body>
        <p>{{i18n "vzekc_verlosung.change_end_date.modal_body"}}</p>
        <div class="control-group change-end-date-field">
          <label for="change-end-date-input">
            {{i18n "vzekc_verlosung.change_end_date.label"}}
          </label>
          <input
            id="change-end-date-input"
            type="datetime-local"
            value={{this.value}}
            min={{this.minValue}}
            {{on "input" this.updateValue}}
          />
        </div>
      </:body>
      <:footer>
        <DButton
          @action={{this.confirm}}
          @label="vzekc_verlosung.change_end_date.confirm_button"
          @icon={{if this.submitting "spinner" "calendar"}}
          @disabled={{this.isDisabled}}
          @isLoading={{this.submitting}}
          class="btn-primary"
        />
        <DButton @action={{@closeModal}} @label="cancel" class="btn-default" />
      </:footer>
    </DModal>
  </template>
}
