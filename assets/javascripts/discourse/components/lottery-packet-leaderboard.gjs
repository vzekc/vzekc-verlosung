import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

/**
 * Displays packet leaderboards: most popular and packets without tickets
 *
 * @component LotteryPacketLeaderboard
 * @param {string} @period - Look-back period ("3m", "6m", "1y" or "all")
 */
export default class LotteryPacketLeaderboard extends Component {
  @tracked data = null;
  @tracked isLoading = true;

  constructor() {
    super(...arguments);
    this.loadData();
  }

  /**
   * Loads the packet leaderboards for the current period. A response for a period that
   * is no longer selected is discarded.
   */
  @action
  async loadData() {
    const period = this.args.period;
    this.isLoading = true;
    try {
      const result = await ajax("/vzekc-verlosung/history/packets.json", {
        data: { period },
      });
      if (period === this.args.period) {
        this.data = result;
      }
    } finally {
      if (period === this.args.period) {
        this.isLoading = false;
      }
    }
  }

  <template>
    <div class="lottery-packet-leaderboard" {{didUpdate this.loadData @period}}>
      {{#if this.isLoading}}
        <div class="packet-leaderboard-loading">
          {{icon "spinner" class="fa-spin"}}
          {{i18n "loading"}}
        </div>
      {{else if this.data}}
        <div class="packet-leaderboard-columns">
          {{! Popular packets }}
          <div class="packet-leaderboard-section">
            <h3 class="packet-leaderboard-title">
              {{icon "fire"}}
              {{i18n "vzekc_verlosung.history.packet_leaderboard.popular"}}
            </h3>
            {{#if this.data.popular.length}}
              <ul class="packet-leaderboard-list">
                {{#each this.data.popular as |packet|}}
                  <li class="packet-leaderboard-entry">
                    <div class="packet-info">
                      <a href={{packet.url}} class="packet-title">
                        {{packet.title}}
                      </a>
                      <span class="lottery-ref">
                        <a
                          href={{packet.lottery.url}}
                        >{{packet.lottery.title}}</a>
                      </span>
                    </div>
                    <span
                      class="ticket-count"
                      title={{i18n
                        "vzekc_verlosung.history.packet_leaderboard.tickets_title"
                      }}
                    >
                      {{icon "ticket"}}
                      {{packet.ticket_count}}
                    </span>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class="no-data">{{i18n
                  "vzekc_verlosung.history.packet_leaderboard.no_data"
                }}</p>
            {{/if}}
          </div>

          {{! Packets without tickets }}
          <div class="packet-leaderboard-section">
            <h3 class="packet-leaderboard-title">
              {{icon "ticket"}}
              {{i18n "vzekc_verlosung.history.packet_leaderboard.no_tickets"}}
            </h3>
            {{#if this.data.no_tickets.length}}
              <ul class="packet-leaderboard-list">
                {{#each this.data.no_tickets as |packet|}}
                  <li class="packet-leaderboard-entry">
                    <div class="packet-info">
                      <a href={{packet.url}} class="packet-title">
                        {{packet.title}}
                      </a>
                      <span class="lottery-ref">
                        <a
                          href={{packet.lottery.url}}
                        >{{packet.lottery.title}}</a>
                      </span>
                    </div>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class="no-data">{{i18n
                  "vzekc_verlosung.history.packet_leaderboard.no_data"
                }}</p>
            {{/if}}
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
