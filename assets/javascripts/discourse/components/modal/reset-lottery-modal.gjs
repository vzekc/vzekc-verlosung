import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * Modal for relisting a lottery that ended without participants
 *
 * @component ResetLotteryModal
 * @param {Number} model.topicId - Topic ID of the lottery
 * @param {Number} model.defaultDurationDays - Duration to preselect (7-28)
 */
export default class ResetLotteryModal extends Component {
  @tracked durationDays = this.args.model.defaultDurationDays || 14;
  @tracked submitting = false;

  get durationOptions() {
    return [7, 14, 21, 28];
  }

  @action
  updateDuration(event) {
    this.durationDays = parseInt(event.target.value, 10);
  }

  @action
  async confirm() {
    this.submitting = true;
    try {
      await ajax(
        `/vzekc-verlosung/lotteries/${this.args.model.topicId}/reset`,
        {
          type: "POST",
          data: { duration_days: this.durationDays },
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
      @title={{i18n "vzekc_verlosung.reset_lottery.modal_title"}}
      @closeModal={{@closeModal}}
      class="reset-lottery-modal"
    >
      <:body>
        <p>{{i18n "vzekc_verlosung.reset_lottery.modal_body"}}</p>
        <div class="control-group reset-duration-field">
          <label for="reset-lottery-duration">
            {{i18n "vzekc_verlosung.reset_lottery.duration_label"}}
          </label>
          <select
            id="reset-lottery-duration"
            {{on "change" this.updateDuration}}
          >
            {{#each this.durationOptions as |days|}}
              <option
                value={{days}}
                selected={{if (eq days this.durationDays) "selected"}}
              >
                {{days}}
              </option>
            {{/each}}
          </select>
        </div>
      </:body>
      <:footer>
        <DButton
          @action={{this.confirm}}
          @label="vzekc_verlosung.reset_lottery.confirm_button"
          @icon={{if this.submitting "spinner" "rotate"}}
          @disabled={{this.submitting}}
          @isLoading={{this.submitting}}
          class="btn-primary"
        />
        <DButton @action={{@closeModal}} @label="cancel" class="btn-default" />
      </:footer>
    </DModal>
  </template>
}
