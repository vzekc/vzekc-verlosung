import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
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

  @tracked hasTicket = false;
  @tracked ticketCount = 0;
  @tracked users = [];
  @tracked loading = true;

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
   * Get the winner username for this packet
   *
   * @type {string|null}
   */
  get winner() {
    return this.post?.lottery_winner;
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

  <template>
    {{#if this.shouldShow}}
      <div class="lottery-packet-status">
        {{#if this.isDrawn}}
          {{! Lottery has been drawn - show winner or no winner message }}
          {{#if this.winner}}
            <div class="lottery-packet-winner-notice">
              <div class="winner-message">
                <span class="winner-label">{{i18n
                    "vzekc_verlosung.ticket.winner"
                  }}</span>
                <UserLink @username={{this.winner}} class="winner-user-link">
                  {{avatar (hash username=this.winner) imageSize="small"}}
                  <span class="winner-name">{{this.winner}}</span>
                </UserLink>
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
        {{/if}}
      </div>
    {{/if}}
  </template>
}
