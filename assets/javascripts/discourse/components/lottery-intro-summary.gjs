import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";

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

  <template>
    <div class="lottery-intro-summary">
      {{#if this.loading}}
        <div class="lottery-intro-loading">
          {{icon "spinner" class="fa-spin"}}
        </div>
      {{else}}
        {{#if this.packets.length}}
          <h3 class="lottery-packets-title">Pakete</h3>
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
