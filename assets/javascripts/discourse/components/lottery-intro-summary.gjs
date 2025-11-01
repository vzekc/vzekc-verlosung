import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import { i18n } from "discourse-i18n";

/**
 * Component to display lottery packet summary on lottery intro posts
 *
 * @component LotteryIntroSummary
 * Shows a list of lottery packets with their ticket counts
 *
 * @param {Object} data.post - The lottery intro post object
 */
export default class LotteryIntroSummary extends Component {
  @service currentUser;
  @service appEvents;

  @tracked packets = [];
  @tracked loading = true;
  @tracked publishing = false;

  constructor() {
    super(...arguments);
    this.loadPackets();
    this.appEvents.on("lottery:ticket-changed", this, this.onTicketChanged);
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.appEvents.off("lottery:ticket-changed", this, this.onTicketChanged);
  }

  @bind
  onTicketChanged(postId) {
    // Check if the changed post is one of our packets
    const packet = this.packets.find((p) => p.post_id === postId);
    if (packet) {
      this.loadPackets();
    }
  }

  /**
   * Load the list of packets for this lottery
   */
  async loadPackets() {
    try {
      const result = await ajax(
        `/vzekc-verlosung/lotteries/${this.args.data.post.topic_id}/packets`
      );
      this.packets = result.packets || [];
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * Get the topic object
   *
   * @returns {Object} the topic object
   */
  get topic() {
    return this.args.data.post.topic;
  }

  /**
   * Check if this lottery is a draft
   *
   * @returns {Boolean} true if the lottery is in draft state
   */
  get isDraft() {
    return this.topic?.lottery_draft === true;
  }

  /**
   * Check if current user can publish this lottery
   *
   * @returns {Boolean} true if user can publish
   */
  get canPublish() {
    if (!this.currentUser) {
      return false;
    }
    if (this.currentUser.staff) {
      return true;
    }
    return this.args.data.post.user_id === this.currentUser.id;
  }

  /**
   * Publish the lottery (remove draft status)
   */
  @action
  async publishLottery() {
    if (this.publishing) {
      return;
    }

    this.publishing = true;
    try {
      await ajax(
        `/vzekc-verlosung/lotteries/${this.args.data.post.topic_id}/publish`,
        {
          type: "PUT",
        }
      );
      // Reload the page to show the published state
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.publishing = false;
    }
  }

  <template>
    <div class="lottery-intro-summary">
      {{#if this.loading}}
        <div class="lottery-intro-loading">
          {{icon "spinner" class="fa-spin"}}
        </div>
      {{else}}
        {{#if this.isDraft}}
          {{#if this.canPublish}}
            <div class="lottery-draft-notice">
              <div class="draft-message">
                {{icon "lock"}}
                <span>{{i18n "vzekc_verlosung.draft.notice"}}</span>
              </div>
              <DButton
                @action={{this.publishLottery}}
                @translatedLabel={{i18n "vzekc_verlosung.draft.publish_button"}}
                @icon="paper-plane"
                @disabled={{this.publishing}}
                class="btn-primary lottery-publish-button"
              />
            </div>
          {{/if}}
        {{/if}}

        {{#if this.packets.length}}
          <h3 class="lottery-packets-title">{{i18n
              "vzekc_verlosung.packets_title"
            }}</h3>
          <ul class="lottery-packets-list">
            {{#each this.packets as |packet|}}
              <li class="lottery-packet-item">
                <a
                  href="#post_{{packet.post_number}}"
                  class="packet-title"
                >{{packet.title}}</a>
                <span class="packet-ticket-count">
                  {{icon "gift"}}
                  <span class="count">{{packet.ticket_count}}</span>
                </span>
              </li>
            {{/each}}
          </ul>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
