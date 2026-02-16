import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

/**
 * Confirmation page for silencing owner reminders on a lottery
 *
 * @component SilenceRemindersPage
 * @param {Object} model - Route model
 * @param {number} model.topicId - Topic ID of the lottery
 */
export default class SilenceRemindersPage extends Component {
  @service router;

  @tracked loading = true;
  @tracked silenced = false;
  @tracked submitting = false;
  @tracked error = null;
  @tracked topicTitle = null;
  @tracked topicUrl = null;

  constructor() {
    super(...arguments);
    this.loadTopic();
  }

  /**
   * Load topic info to display the lottery title
   */
  async loadTopic() {
    try {
      const data = await ajax(`/t/${this.args.model.topicId}.json`);
      this.topicTitle = data.title;
      this.topicUrl = data.fancy_title
        ? `/t/${data.slug}/${data.id}`
        : `/t/${data.id}`;
    } catch {
      this.error = i18n("vzekc_verlosung.silence_reminders.error_not_found");
    } finally {
      this.loading = false;
    }
  }

  /**
   * Confirm silencing reminders
   */
  @action
  async confirm() {
    this.submitting = true;
    this.error = null;

    try {
      await ajax(
        `/vzekc-verlosung/lotteries/${this.args.model.topicId}/silence-reminders`,
        { type: "PUT" }
      );
      this.silenced = true;
    } catch (e) {
      this.error = extractError(e);
    } finally {
      this.submitting = false;
    }
  }

  /**
   * Navigate to the lottery topic
   */
  @action
  cancel() {
    if (this.topicUrl) {
      this.router.transitionTo(this.topicUrl);
    } else {
      this.router.transitionTo("/");
    }
  }

  <template>
    <div class="silence-reminders-page">
      {{#if this.loading}}
        <div class="spinner-container">
          <div class="spinner"></div>
        </div>
      {{else if this.silenced}}
        <div class="silence-reminders-success">
          <h2>{{i18n "vzekc_verlosung.silence_reminders.title"}}</h2>
          <p>{{i18n "vzekc_verlosung.silence_reminders.success"}}</p>
          {{#if this.topicUrl}}
            <DButton
              @action={{this.cancel}}
              @label="vzekc_verlosung.silence_reminders.cancel_button"
              class="btn-primary"
            />
          {{/if}}
        </div>
      {{else}}
        <div class="silence-reminders-confirm">
          <h2>{{i18n "vzekc_verlosung.silence_reminders.title"}}</h2>
          {{#if this.topicTitle}}
            <p class="lottery-title"><strong>{{this.topicTitle}}</strong></p>
          {{/if}}
          <p>{{i18n "vzekc_verlosung.silence_reminders.description"}}</p>
          {{#if this.error}}
            <div class="alert alert-error">{{this.error}}</div>
          {{/if}}
          <div class="silence-reminders-actions">
            <DButton
              @action={{this.confirm}}
              @label="vzekc_verlosung.silence_reminders.confirm_button"
              @disabled={{this.submitting}}
              class="btn-primary"
            />
            <DButton
              @action={{this.cancel}}
              @label="vzekc_verlosung.silence_reminders.cancel_button"
              class="btn-default"
            />
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
