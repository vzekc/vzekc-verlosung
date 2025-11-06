import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import UserLink from "discourse/components/user-link";
import avatar from "discourse/helpers/avatar";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import { i18n } from "discourse-i18n";
import TicketCountBadge from "./ticket-count-badge";

/**
 * Lottery widget component combining ticket button and count display
 *
 * @component LotteryWidget
 * Shows a button to buy/return lottery tickets and displays the ticket count with participants
 *
 * @param {Object} args.data.post - The post object (passed via renderGlimmer)
 */
export default class LotteryWidget extends Component {
  @service currentUser;
  @service appEvents;
  @service modal;

  @tracked hasTicket = false;
  @tracked ticketCount = 0;
  @tracked users = [];
  @tracked winnerData = null;
  @tracked collectedAt = null;
  @tracked loading = true;
  @tracked markingCollected = false;

  constructor() {
    super(...arguments);
    if (this.shouldShow) {
      this.loadTicketData();
      this.appEvents.on("lottery:ticket-changed", this, this.onTicketChanged);
    } else {
      this.loading = false;
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    if (this.shouldShow) {
      this.appEvents.off("lottery:ticket-changed", this, this.onTicketChanged);
    }
  }

  /**
   * Get the post object from component args
   *
   * @type {Object}
   */
  get post() {
    return this.args.data?.post;
  }

  @bind
  onTicketChanged(postId) {
    if (postId === this.post?.id) {
      this.loadTicketData();
    }
  }

  /**
   * Load ticket data for this lottery packet post including user's ticket status and count
   */
  async loadTicketData() {
    try {
      const result = await ajax(
        `/vzekc-verlosung/tickets/packet-status/${this.post.id}`
      );
      this.hasTicket = result.has_ticket;
      this.ticketCount = result.ticket_count;
      this.users = result.users || [];
      this.winnerData = result.winner || null;
      this.collectedAt = result.collected_at || null;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * Toggle ticket status (buy or return)
   */
  @action
  async toggleTicket() {
    if (this.loading) {
      return;
    }

    this.loading = true;

    try {
      if (this.hasTicket) {
        // Return ticket
        await ajax(`/vzekc-verlosung/tickets/${this.post.id}`, {
          type: "DELETE",
        });
        this.hasTicket = false;
      } else {
        // Buy ticket
        await ajax("/vzekc-verlosung/tickets", {
          type: "POST",
          data: { post_id: this.post.id },
        });
        this.hasTicket = true;
      }

      // Emit event to update ticket count display
      this.appEvents.trigger("lottery:ticket-changed", this.post.id);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * Check if this widget should be shown
   * Only show on lottery packet posts for logged-in users
   *
   * @type {boolean}
   */
  get shouldShow() {
    return this.currentUser && this.post?.is_lottery_packet;
  }

  /**
   * Check if user can buy or return tickets
   * Returns false if lottery is not active or has ended
   *
   * @type {boolean}
   */
  get canBuyOrReturn() {
    const topic = this.post?.topic;

    // Check if lottery is active (not draft, not finished)
    if (topic?.lottery_state !== "active") {
      return false;
    }

    // Check if lottery has ended
    if (topic?.lottery_ends_at) {
      const endsAt = new Date(topic.lottery_ends_at);
      if (endsAt <= new Date()) {
        return false;
      }
    }
    return true;
  }

  /**
   * Check if lottery has ended
   *
   * @type {boolean}
   */
  get hasEnded() {
    const topic = this.post?.topic;
    if (topic?.lottery_ends_at) {
      const endsAt = new Date(topic.lottery_ends_at);
      return endsAt <= new Date();
    }
    return false;
  }

  /**
   * Check if lottery has been drawn
   *
   * @type {boolean}
   */
  get isDrawn() {
    const topic = this.post?.topic;
    return topic?.lottery_results != null;
  }

  /**
   * Get the winner for this packet
   * Prefers loaded winnerData from API, falls back to post custom field
   *
   * @type {Object|string|null}
   */
  get winner() {
    // Prefer the winner data loaded from API (includes avatar)
    if (this.winnerData) {
      return this.winnerData;
    }
    // Fall back to post custom field (just username string)
    return this.post?.lottery_winner;
  }

  /**
   * Get winner username (handles both string and object)
   *
   * @type {string|null}
   */
  get winnerUsername() {
    const winner = this.winner;
    if (!winner) {
      return null;
    }
    return typeof winner === "string" ? winner : winner.username;
  }

  /**
   * Check if winner is a full user object with avatar_template
   *
   * @type {boolean}
   */
  get hasWinnerObject() {
    const winner = this.winner;
    return winner && typeof winner === "object" && winner.avatar_template;
  }

  /**
   * Get the button label based on ticket status
   *
   * @type {string}
   */
  get buttonLabel() {
    if (this.loading) {
      return "vzekc_verlosung.ticket.loading";
    }
    return this.hasTicket
      ? "vzekc_verlosung.ticket.return"
      : "vzekc_verlosung.ticket.buy";
  }

  /**
   * Get the button icon based on ticket status
   *
   * @type {string}
   */
  get buttonIcon() {
    return this.hasTicket ? "xmark" : "gift";
  }

  /**
   * Extract packet title from post content (first heading)
   *
   * @type {string}
   */
  get packetTitle() {
    if (!this.post?.cooked) {
      return "";
    }
    const tempDiv = document.createElement("div");
    tempDiv.innerHTML = this.post.cooked;
    const heading = tempDiv.querySelector("h1, h2, h3");
    return heading ? heading.textContent.trim() : "";
  }

  /**
   * Check if current user is the lottery owner
   *
   * @type {boolean}
   */
  get isLotteryOwner() {
    const topic = this.post?.topic;
    return (
      this.currentUser &&
      topic &&
      (this.currentUser.admin ||
        this.currentUser.staff ||
        topic.user_id === this.currentUser.id)
    );
  }

  /**
   * Check if the "Mark as Collected" button should be shown
   *
   * @type {boolean}
   */
  get canMarkAsCollected() {
    return (
      this.isLotteryOwner && this.winner && !this.collectedAt && !this.loading
    );
  }

  /**
   * Format collected date for display
   *
   * @type {string|null}
   */
  get formattedCollectedDate() {
    if (!this.collectedAt) {
      return null;
    }
    const date = new Date(this.collectedAt);
    return date.toLocaleDateString();
  }

  /**
   * Mark packet as collected (with confirmation)
   */
  @action
  async markAsCollected() {
    if (this.markingCollected) {
      return;
    }

    const confirmed = await this.modal.confirm({
      title: i18n("vzekc_verlosung.collection.confirm_title"),
      message: i18n("vzekc_verlosung.collection.confirm_message", {
        winner: this.winnerUsername,
        packet: this.packetTitle,
      }),
      confirmButtonLabel: i18n("vzekc_verlosung.collection.confirm_button"),
      confirmButtonClass: "btn-primary",
      cancelButtonLabel: i18n("cancel"),
    });

    if (!confirmed) {
      return;
    }

    this.markingCollected = true;

    try {
      const result = await ajax(
        `/vzekc-verlosung/packets/${this.post.id}/mark-collected`,
        {
          type: "POST",
        }
      );

      // Update local state with response
      this.collectedAt = result.collected_at || null;

      // Show success message
      this.modal.alert({
        title: i18n("vzekc_verlosung.collection.success_title"),
        message: i18n("vzekc_verlosung.collection.success_message"),
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.markingCollected = false;
    }
  }

  <template>
    {{#if this.shouldShow}}
      <div class="lottery-packet-status">
        {{#if this.isDrawn}}
          {{! Lottery has been drawn - show winner or no winner message }}
          {{#if this.winner}}
            <div class="lottery-packet-winner-notice">
              {{#unless this.loading}}
                <div class="participants-display">
                  <span class="participants-label">{{i18n
                      "vzekc_verlosung.ticket.participants"
                    }}</span>
                  <TicketCountBadge
                    @count={{this.ticketCount}}
                    @users={{this.users}}
                    @packetTitle={{this.packetTitle}}
                  />
                </div>
              {{/unless}}
              <div class="winner-message">
                <span class="participants-label">{{i18n
                    "vzekc_verlosung.ticket.winner"
                  }}</span>
                {{#if this.hasWinnerObject}}
                  <UserLink
                    @username={{this.winnerUsername}}
                    class="winner-user-link"
                  >
                    {{avatar this.winner imageSize="small"}}
                    <span class="winner-name">{{this.winnerUsername}}</span>
                  </UserLink>
                {{else}}
                  <UserLink
                    @username={{this.winnerUsername}}
                    class="winner-user-link"
                  >
                    <span class="winner-name">{{this.winnerUsername}}</span>
                  </UserLink>
                {{/if}}
              </div>
              {{! Collection tracking - only visible to lottery owner }}
              {{#if this.isLotteryOwner}}
                <div class="collection-tracking">
                  {{#if this.collectedAt}}
                    <div class="collection-status collected">
                      <span class="collection-icon">✓</span>
                      <span class="collection-text">{{i18n
                          "vzekc_verlosung.collection.collected_on"
                          date=this.formattedCollectedDate
                        }}</span>
                    </div>
                  {{else if this.canMarkAsCollected}}
                    <DButton
                      @action={{this.markAsCollected}}
                      @label="vzekc_verlosung.collection.mark_collected"
                      @icon="check"
                      @disabled={{this.markingCollected}}
                      class="btn-default mark-collected-button"
                    />
                  {{/if}}
                </div>
              {{/if}}
            </div>
          {{else}}
            <div class="lottery-packet-no-winner-notice">
              <div class="no-winner-message">{{i18n
                  "vzekc_verlosung.ticket.no_winner"
                }}</div>
            </div>
          {{/if}}
        {{else if this.canBuyOrReturn}}
          {{! Lottery is active - show buy/return button }}
          <div class="lottery-packet-active-notice">
            <div class="action-section">
              <DButton
                @action={{this.toggleTicket}}
                @label={{this.buttonLabel}}
                @icon={{this.buttonIcon}}
                @disabled={{this.loading}}
                class="btn-primary lottery-ticket-button"
              />
            </div>
            {{#unless this.loading}}
              <div class="participants-display">
                <span class="participants-label">{{i18n
                    "vzekc_verlosung.ticket.participants"
                  }}</span>
                <TicketCountBadge
                  @count={{this.ticketCount}}
                  @users={{this.users}}
                  @packetTitle={{this.packetTitle}}
                />
              </div>
            {{/unless}}
          </div>
        {{else if this.hasEnded}}
          {{! Lottery has ended but not drawn yet - show participants only }}
          <div class="lottery-packet-ended-notice">
            {{#unless this.loading}}
              <div class="participants-display">
                <span class="participants-label">{{i18n
                    "vzekc_verlosung.ticket.participants"
                  }}</span>
                <TicketCountBadge
                  @count={{this.ticketCount}}
                  @users={{this.users}}
                  @packetTitle={{this.packetTitle}}
                  @hasEnded={{true}}
                />
              </div>
            {{/unless}}
          </div>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
