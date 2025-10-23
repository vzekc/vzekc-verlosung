import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

/**
 * Button component for buying/returning lottery tickets
 *
 * @component LotteryTicketButton
 * Shows a button on lottery packet posts to buy or return tickets
 *
 * @param {Object} args.post - The post object
 */
export default class LotteryTicketButton extends Component {
  @service currentUser;
  @service appEvents;
  @tracked hasTicket = false;
  @tracked loading = true;

  constructor() {
    super(...arguments);
    this.loadTicketStatus();
  }

  /**
   * Load the ticket status for this post
   */
  async loadTicketStatus() {
    if (!this.currentUser) {
      this.loading = false;
      return;
    }

    try {
      const result = await ajax(
        `/vzekc-verlosung/tickets/status/${this.args.post.id}`
      );
      this.hasTicket = result.has_ticket;
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

  /**
   * Check if this button should be shown
   * Only show on lottery packet posts
   *
   * @type {boolean}
   */
  get shouldShow() {
    const isLotteryPacket = this.args.post?.is_lottery_packet;
    // Only show if user is logged in and this is a lottery packet post
    return this.currentUser && isLotteryPacket;
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

  <template>
    {{#if this.shouldShow}}
      <DButton
        @action={{this.toggleTicket}}
        @label={{this.buttonLabel}}
        @icon={{this.buttonIcon}}
        @disabled={{this.loading}}
        class="btn-primary lottery-ticket-button"
      />
    {{/if}}
  </template>
}
