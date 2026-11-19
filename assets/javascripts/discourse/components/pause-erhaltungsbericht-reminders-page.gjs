import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import DiscourseURL from "discourse/lib/url";
import I18n, { i18n } from "discourse-i18n";

/**
 * Landing page for the pause link in Erhaltungsbericht reminder PMs. Lets the
 * winner pause the reminders until six months after receiving the packet, or
 * resume them.
 *
 * @component PauseErhaltungsberichtRemindersPage
 * @param {Object} model - Route model
 * @param {number} model.postId - Post ID of the packet
 * @param {Object} model.state - Reminder state from the server
 * @param {string} model.error - Message explaining why the state is unavailable
 */
export default class PauseErhaltungsberichtRemindersPage extends Component {
  /**
   * Reminder state returned by the last pause or resume
   *
   * @type {Object|null}
   */
  @tracked updatedState = null;

  /**
   * Error of the last pause or resume
   *
   * @type {string|null}
   */
  @tracked updateError = null;

  /**
   * @type {boolean}
   */
  @tracked submitting = false;

  /**
   * Reminder state, as last returned by the server
   *
   * @returns {Object|null}
   */
  get state() {
    return this.updatedState || this.args.model.state;
  }

  /**
   * @returns {string|null}
   */
  get error() {
    return this.updateError || this.args.model.error;
  }

  /**
   * @returns {string}
   */
  get packetLabel() {
    const { packet_title, lottery_title } = this.state;
    return packet_title && packet_title !== lottery_title
      ? `${packet_title} — ${lottery_title}`
      : lottery_title;
  }

  /**
   * @returns {string}
   */
  get deadline() {
    return this.formatDate(this.state.silence_deadline);
  }

  /**
   * @returns {string}
   */
  get silencedUntil() {
    return this.formatDate(this.state.silenced_until);
  }

  /**
   * @returns {string}
   */
  get confirmLabel() {
    return i18n(
      "vzekc_verlosung.pause_erhaltungsbericht_reminders.confirm_button",
      {
        date: this.deadline,
      }
    );
  }

  /**
   * @param {string} value - ISO timestamp
   * @returns {string}
   */
  formatDate(value) {
    if (!value) {
      return "";
    }
    return new Date(value).toLocaleDateString(I18n.locale || "de", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  }

  /**
   * Pause the reminders until the end of the silence period
   */
  @action
  async pause() {
    await this.update(true);
  }

  /**
   * Resume the weekly reminders
   */
  @action
  async resume() {
    await this.update(false);
  }

  /**
   * Store the pause state on the server
   *
   * @param {boolean} silenced
   */
  async update(silenced) {
    this.submitting = true;
    this.updateError = null;

    try {
      this.updatedState = await ajax(
        `/vzekc-verlosung/packets/${this.args.model.postId}/erhaltungsbericht-reminders`,
        { type: "PUT", data: { silenced } }
      );
    } catch (e) {
      this.updateError = extractError(e);
    } finally {
      this.submitting = false;
    }
  }

  /**
   * Navigate to the packet post
   */
  @action
  goToPacket() {
    DiscourseURL.routeTo(
      this.state?.packet_url || `/p/${this.args.model.postId}`
    );
  }

  <template>
    <div class="pause-erhaltungsbericht-reminders-page">
      <h2>{{i18n
          "vzekc_verlosung.pause_erhaltungsbericht_reminders.title"
        }}</h2>

      {{#if this.state}}
        <p class="packet-label"><strong>{{this.packetLabel}}</strong></p>

        {{#if this.state.has_report}}
          <p>{{i18n
              "vzekc_verlosung.pause_erhaltungsbericht_reminders.has_report"
            }}</p>
        {{else if this.state.silenced_until}}
          <p>{{i18n
              "vzekc_verlosung.pause_erhaltungsbericht_reminders.paused"
              date=this.silencedUntil
            }}</p>
        {{else if this.state.can_silence}}
          <p>{{i18n
              "vzekc_verlosung.pause_erhaltungsbericht_reminders.description"
              date=this.deadline
            }}</p>
        {{else}}
          <p>{{i18n
              "vzekc_verlosung.pause_erhaltungsbericht_reminders.not_possible"
            }}</p>
        {{/if}}
      {{/if}}

      {{#if this.error}}
        <div class="alert alert-error">{{this.error}}</div>
      {{/if}}

      <div class="pause-erhaltungsbericht-reminders-actions">
        {{#if this.state.has_report}}
          {{! a written report ends the reminders }}
        {{else if this.state.silenced_until}}
          <DButton
            @action={{this.resume}}
            @label="vzekc_verlosung.pause_erhaltungsbericht_reminders.resume_button"
            @disabled={{this.submitting}}
            @icon="play"
            class="btn-default"
          />
        {{else if this.state.can_silence}}
          <DButton
            @action={{this.pause}}
            @translatedLabel={{this.confirmLabel}}
            @disabled={{this.submitting}}
            @icon="pause"
            class="btn-primary"
          />
        {{/if}}
        <DButton
          @action={{this.goToPacket}}
          @label="vzekc_verlosung.write_erhaltungsbericht.packet_button"
          class="btn-default"
        />
      </div>
    </div>
  </template>
}
