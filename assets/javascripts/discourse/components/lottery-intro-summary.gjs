import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { and } from "truth-helpers";
import DButton from "discourse/components/d-button";
import UserLink from "discourse/components/user-link";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import { i18n } from "discourse-i18n";
import DrawLotteryModal from "./modal/draw-lottery-modal";
import TicketCountBadge from "./ticket-count-badge";

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
  @service modal;

  @tracked packets = [];
  @tracked loading = true;
  @tracked publishing = false;
  @tracked ending = false;
  @tracked openingDrawModal = false;

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
    return this.topic?.lottery_state === "draft";
  }

  /**
   * Check if this lottery is active
   *
   * @returns {Boolean} true if the lottery is active
   */
  get isActive() {
    return this.topic?.lottery_state === "active";
  }

  /**
   * Check if lottery is active and still running (not ended yet)
   *
   * @returns {Boolean} true if the lottery is active and hasn't ended
   */
  get isRunning() {
    if (!this.isActive || !this.topic?.lottery_ends_at) {
      return false;
    }
    const endsAt = new Date(this.topic.lottery_ends_at);
    const now = new Date();
    return endsAt > now;
  }

  /**
   * Check if this lottery is finished
   *
   * @returns {Boolean} true if the lottery is finished
   */
  get isFinished() {
    return this.topic?.lottery_state === "finished";
  }

  /**
   * Check if lottery has ended
   *
   * @returns {Boolean} true if the lottery has ended
   */
  get hasEnded() {
    if (!this.topic?.lottery_ends_at) {
      return false;
    }
    const endsAt = new Date(this.topic.lottery_ends_at);
    return endsAt <= new Date();
  }

  /**
   * Check if lottery has ended but not been drawn yet
   *
   * @returns {Boolean} true if ready to draw
   */
  get canDraw() {
    if (!this.topic || !this.topic.lottery_ends_at) {
      return false;
    }
    const hasEnded = new Date(this.topic.lottery_ends_at) <= new Date();
    const notDrawn = !this.topic.lottery_results;
    return hasEnded && notDrawn && this.canPublish;
  }

  /**
   * Get the time remaining until the lottery ends
   *
   * @returns {String} formatted time remaining
   */
  get timeRemaining() {
    if (!this.topic?.lottery_ends_at) {
      return null;
    }

    const endsAt = new Date(this.topic.lottery_ends_at);
    const now = new Date();
    const diff = endsAt - now;

    if (diff <= 0) {
      return i18n("vzekc_verlosung.state.ended");
    }

    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));

    if (days > 0) {
      return i18n("vzekc_verlosung.state.time_remaining_days", {
        days,
        hours,
      });
    } else if (hours > 0) {
      return i18n("vzekc_verlosung.state.time_remaining_hours", {
        hours,
        minutes,
      });
    } else {
      return i18n("vzekc_verlosung.state.time_remaining_minutes", {
        minutes,
      });
    }
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
   * Check if current user is the lottery owner
   *
   * @returns {Boolean} true if user is lottery owner or staff
   */
  get isLotteryOwner() {
    return (
      this.currentUser &&
      this.topic &&
      (this.currentUser.admin ||
        this.currentUser.staff ||
        this.topic.user_id === this.currentUser.id)
    );
  }

  /**
   * Format collected date for display
   *
   * @param {String|Date} collectedAt - The collection timestamp
   * @returns {String} formatted date string
   */
  formatCollectedDate(collectedAt) {
    if (!collectedAt) {
      return null;
    }
    const date = new Date(collectedAt);
    return date.toLocaleDateString("de-DE", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  }

  /**
   * Get the publish button label
   *
   * @returns {String} the button label
   */
  get publishButtonLabel() {
    return this.publishing
      ? i18n("vzekc_verlosung.draft.publishing")
      : i18n("vzekc_verlosung.draft.publish_button");
  }

  /**
   * Get the publish button icon
   *
   * @returns {String} the button icon
   */
  get publishButtonIcon() {
    return this.publishing ? "spinner" : "paper-plane";
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
      this.publishing = false;
    }
  }

  /**
   * Open the drawing modal to draw winners
   */
  @action
  async drawWinners() {
    this.openingDrawModal = true;
    try {
      await this.modal.show(DrawLotteryModal, {
        model: {
          topicId: this.args.data.post.topic_id,
        },
      });
    } finally {
      // Reset spinner state when modal closes (whether cancelled or completed)
      this.openingDrawModal = false;
    }
  }

  /**
   * End the lottery early (for testing purposes)
   */
  @action
  async endEarly() {
    if (this.ending) {
      return;
    }

    // eslint-disable-next-line no-alert
    if (!confirm(i18n("vzekc_verlosung.testing.end_early_confirm"))) {
      return;
    }

    this.ending = true;
    try {
      await ajax(
        `/vzekc-verlosung/lotteries/${this.args.data.post.topic_id}/end-early`,
        {
          type: "PUT",
        }
      );
      // Reload the page to show the ended state
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
      this.ending = false;
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
                @translatedLabel={{this.publishButtonLabel}}
                @icon={{this.publishButtonIcon}}
                @disabled={{this.publishing}}
                @isLoading={{this.publishing}}
                class="btn-primary lottery-publish-button"
              />
            </div>
          {{/if}}
        {{/if}}

        {{#if this.isActive}}
          {{#if this.timeRemaining}}
            <div class="lottery-active-notice">
              <div class="active-message">
                {{icon "clock"}}
                <span>{{i18n "vzekc_verlosung.state.active"}}</span>
              </div>
              <div class="time-remaining">
                {{this.timeRemaining}}
              </div>
              {{#if (and this.isRunning this.canPublish)}}
                <DButton
                  @action={{this.endEarly}}
                  @translatedLabel={{if
                    this.ending
                    (i18n "vzekc_verlosung.testing.ending")
                    (i18n "vzekc_verlosung.testing.end_early_button")
                  }}
                  @icon={{if this.ending "spinner" "fast-forward"}}
                  @disabled={{this.ending}}
                  @isLoading={{this.ending}}
                  class="btn-danger btn-small lottery-end-early-button"
                />
              {{/if}}
            </div>
          {{/if}}
        {{/if}}

        {{#if this.canDraw}}
          <div class="lottery-draw-notice">
            <div class="draw-message">
              {{icon "trophy"}}
              <span>{{i18n "vzekc_verlosung.drawing.ready"}}</span>
            </div>
            <DButton
              @action={{this.drawWinners}}
              @translatedLabel={{i18n "vzekc_verlosung.drawing.draw_button"}}
              @icon={{if this.openingDrawModal "spinner" "dice"}}
              @disabled={{this.openingDrawModal}}
              @isLoading={{this.openingDrawModal}}
              class="btn-primary lottery-draw-button"
            />
          </div>
        {{/if}}

        {{#if this.isFinished}}
          <div class="lottery-finished-notice">
            <div class="finished-message">
              {{icon "check-circle"}}
              <span>{{i18n "vzekc_verlosung.state.finished"}}</span>
            </div>
            <div class="download-results">
              <a
                href="/vzekc-verlosung/lotteries/{{this.topic.id}}/results.json"
                class="btn btn-default"
                download
                title={{i18n "vzekc_verlosung.drawing.download_results_help"}}
              >
                {{icon "download"}}
                {{i18n "vzekc_verlosung.drawing.download_results"}}
              </a>
            </div>
          </div>
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
                {{#if this.isFinished}}
                  {{#if packet.winner}}
                    <span class="packet-winner">
                      <span class="participants-label">{{i18n
                          "vzekc_verlosung.ticket.winner"
                        }}</span>
                      <UserLink
                        @username={{packet.winner.username}}
                        class="winner-user-link"
                      >
                        {{avatar packet.winner imageSize="tiny"}}
                        <span
                          class="winner-name"
                        >{{packet.winner.username}}</span>
                      </UserLink>
                      {{#if this.isLotteryOwner}}
                        {{#if packet.collected_at}}
                          <span class="collection-indicator collected">
                            {{icon "check"}}
                            <span
                              class="collection-date"
                            >{{this.formatCollectedDate
                                packet.collected_at
                              }}</span>
                          </span>
                        {{/if}}
                      {{/if}}
                    </span>
                  {{else}}
                    <span class="packet-no-tickets">
                      {{i18n "vzekc_verlosung.ticket.no_tickets"}}
                    </span>
                  {{/if}}
                {{else}}
                  <TicketCountBadge
                    @count={{packet.ticket_count}}
                    @users={{packet.users}}
                    @packetTitle={{packet.title}}
                    @hasEnded={{this.hasEnded}}
                  />
                {{/if}}
              </li>
            {{/each}}
          </ul>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
