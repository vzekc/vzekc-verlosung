import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import DButton from "discourse/components/d-button";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";

/**
 * Lottery widget component combining ticket button and count display
 *
 * @component LotteryWidget
 * Shows a button to buy/return lottery tickets and displays the ticket count with participants
 *
 * @param {Object} args.post - The post object
 */
export default class LotteryWidget extends Component {
  @service currentUser;
  @service appEvents;

  @tracked hasTicket = false;
  @tracked ticketCount = 0;
  @tracked users = [];
  @tracked loading = true;
  @tracked showTooltip = false;

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

  @bind
  onTicketChanged(postId) {
    if (postId === this.args.post?.id) {
      this.loadTicketData();
    }
  }

  /**
   * Load ticket data for this lottery packet post including user's ticket status and count
   */
  async loadTicketData() {
    try {
      const result = await ajax(
        `/vzekc-verlosung/tickets/packet-status/${this.args.post.id}`
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
        await ajax(`/vzekc-verlosung/tickets/${this.args.post.id}`, {
          type: "DELETE",
        });
        this.hasTicket = false;
      } else {
        // Buy ticket
        await ajax("/vzekc-verlosung/tickets", {
          type: "POST",
          data: { post_id: this.args.post.id },
        });
        this.hasTicket = true;
      }

      // Emit event to update ticket count display
      this.appEvents.trigger("lottery:ticket-changed", this.args.post.id);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  showTooltipAction(event) {
    const badge = event.currentTarget;
    const rect = badge.getBoundingClientRect();

    // Position tooltip right-aligned above the badge
    this.tooltipRight = window.innerWidth - rect.right;
    this.tooltipTop = rect.top - 10; // 10px above the badge

    this.showTooltip = true;
  }

  @action
  hideTooltipAction() {
    this.showTooltip = false;
  }

  /**
   * Check if this widget should be shown
   * Only show on lottery packet posts for logged-in users
   *
   * @type {boolean}
   */
  get shouldShow() {
    return this.currentUser && this.args.post?.is_lottery_packet;
  }

  /**
   * Check if user can buy or return tickets
   * Returns false if lottery has ended
   *
   * @type {boolean}
   */
  get canBuyOrReturn() {
    const topic = this.args.post?.topic;
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
    const topic = this.args.post?.topic;
    if (topic?.lottery_ends_at) {
      const endsAt = new Date(topic.lottery_ends_at);
      return endsAt <= new Date();
    }
    return false;
  }

  /**
   * Get the winner username for this packet
   *
   * @type {string|null}
   */
  get winner() {
    return this.args.post?.lottery_winner;
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
   * Get the tooltip style for positioning
   *
   * @type {string}
   */
  get tooltipStyle() {
    if (!this.showTooltip) {
      return htmlSafe(
        "visibility: hidden; opacity: 0; left: auto; right: auto;"
      );
    }

    const style = `visibility: visible; opacity: 1; left: auto; right: ${this.tooltipRight}px; top: ${this.tooltipTop}px; transform: translateY(-100%); position: fixed;`;
    return htmlSafe(style);
  }

  <template>
    {{#if this.shouldShow}}
      {{#if this.canBuyOrReturn}}
        <DButton
          @action={{this.toggleTicket}}
          @label={{this.buttonLabel}}
          @icon={{this.buttonIcon}}
          @disabled={{this.loading}}
          class="btn-primary lottery-ticket-button"
        />
      {{else if this.winner}}
        <div class="lottery-winner-display">
          {{icon "trophy"}}
          <span class="winner-label">Winner:</span>
          <span class="winner-name">{{this.winner}}</span>
        </div>
      {{/if}}
      {{#unless this.loading}}
        <span
          class="lottery-ticket-count-display"
          {{on "mouseenter" this.showTooltipAction}}
          {{on "mouseleave" this.hideTooltipAction}}
        >
          <span class="ticket-count-badge">
            {{icon "gift"}}
            <span class="count">{{this.ticketCount}}</span>
          </span>
        </span>
        {{#if this.ticketCount}}
          <div
            class="ticket-users-tooltip-wrapper"
            style="position: fixed; width: 0; height: 0; pointer-events: none;"
          >
            <div class="ticket-users-tooltip" style={{this.tooltipStyle}}>
              <div class="ticket-users-list">
                {{#each this.users as |user|}}
                  <div class="ticket-user">
                    {{avatar user imageSize="tiny"}}
                    <span class="username">{{user.username}}</span>
                  </div>
                {{/each}}
              </div>
            </div>
          </div>
        {{/if}}
      {{/unless}}
    {{/if}}
  </template>
}
