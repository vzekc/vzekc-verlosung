import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { action } from "@ember/object";
import { htmlSafe } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import icon from "discourse-common/helpers/d-icon";
import avatar from "discourse/helpers/avatar";
import { bind } from "discourse-common/utils/decorators";
import { on } from "@ember/modifier";

/**
 * Component to display ticket count and participants for lottery packets
 */
export default class LotteryTicketCount extends Component {
  @service currentUser;
  @service appEvents;
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
    this.appEvents.off("lottery:ticket-changed", this, this.onTicketChanged);
  }

  @bind
  onTicketChanged(postId) {
    if (postId === this.args.post?.id) {
      this.loadTicketData();
    }
  }

  async loadTicketData() {
    try {
      const result = await ajax(
        `/vzekc-verlosung/tickets/status/${this.args.post.id}`
      );
      this.ticketCount = result.ticket_count;
      this.users = result.users || [];
    } catch (error) {
      console.error("Failed to load ticket data:", error);
    } finally {
      this.loading = false;
    }
  }

  get shouldShow() {
    return this.currentUser && this.args.post?.is_lottery_packet;
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

  get tooltipStyle() {
    if (!this.showTooltip) {
      return htmlSafe("visibility: hidden; opacity: 0; left: auto; right: auto;");
    }

    const style = `visibility: visible; opacity: 1; left: auto; right: ${this.tooltipRight}px; top: ${this.tooltipTop}px; transform: translateY(-100%); position: fixed;`;
    return htmlSafe(style);
  }

  <template>
    {{#if this.shouldShow}}
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
          <div class="ticket-users-tooltip-wrapper" style="position: fixed; width: 0; height: 0; pointer-events: none;">
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
