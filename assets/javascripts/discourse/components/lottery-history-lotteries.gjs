import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { includes } from "discourse/truth-helpers";
import I18n, { i18n } from "discourse-i18n";

/**
 * Displays lotteries grouped with collapsible packet details
 *
 * @component LotteryHistoryLotteries
 */
export default class LotteryHistoryLotteries extends Component {
  @tracked lotteries = [];
  @tracked isLoading = true;
  @tracked expandedIds = [];
  @tracked page = 1;
  @tracked hasMore = true;
  @tracked isLoadingMore = false;

  constructor() {
    super(...arguments);
    this.loadLotteries();
  }

  async loadLotteries() {
    try {
      const result = await ajax("/vzekc-verlosung/history/lotteries.json", {
        data: { page: this.page, per_page: 20 },
      });
      this.lotteries = result.lotteries;
      this.hasMore = result.lotteries.length === 20;
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async loadMore() {
    if (this.isLoadingMore || !this.hasMore) {
      return;
    }

    this.isLoadingMore = true;
    try {
      this.page += 1;
      const result = await ajax("/vzekc-verlosung/history/lotteries.json", {
        data: { page: this.page, per_page: 20 },
      });
      this.lotteries = [...this.lotteries, ...result.lotteries];
      this.hasMore = result.lotteries.length === 20;
    } finally {
      this.isLoadingMore = false;
    }
  }

  @action
  toggleExpanded(lotteryId) {
    if (this.expandedIds.includes(lotteryId)) {
      this.expandedIds = this.expandedIds.filter((id) => id !== lotteryId);
    } else {
      this.expandedIds = [...this.expandedIds, lotteryId];
    }
  }

  /**
   * Format a date as absolute date string
   *
   * @param {String|Date} dateValue - The date to format
   * @returns {String} formatted date string
   */
  @action
  formatAbsoluteDate(dateValue) {
    if (!dateValue) {
      return "-";
    }
    const date = new Date(dateValue);
    const locale = I18n.locale || "de";
    return date.toLocaleDateString(locale, {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  }

  <template>
    <div class="lottery-history-lotteries">
      {{#if this.isLoading}}
        <div class="lotteries-loading">
          {{icon "spinner" class="fa-spin"}}
          {{i18n "loading"}}
        </div>
      {{else if this.lotteries.length}}
        <div class="lotteries-list">
          {{#each this.lotteries as |lottery|}}
            <div
              class="lottery-card
                {{if (includes this.expandedIds lottery.id) 'expanded'}}"
            >
              <div class="lottery-card-header">
                <div class="lottery-info">
                  <button
                    type="button"
                    class="expand-toggle"
                    {{on "click" (fn this.toggleExpanded lottery.id)}}
                    aria-expanded={{if
                      (includes this.expandedIds lottery.id)
                      "true"
                      "false"
                    }}
                  >
                    {{#if (includes this.expandedIds lottery.id)}}
                      {{icon "chevron-down"}}
                    {{else}}
                      {{icon "chevron-right"}}
                    {{/if}}
                  </button>
                  <a href={{lottery.url}} class="lottery-title">
                    {{lottery.title}}
                  </a>
                </div>
                <div class="lottery-meta">
                  <span
                    class="meta-item"
                    title={{i18n "vzekc_verlosung.history.ended"}}
                  >
                    {{icon "calendar"}}
                    {{this.formatAbsoluteDate lottery.ends_at}}
                  </span>
                  <span
                    class="meta-item"
                    title={{i18n "vzekc_verlosung.history.participants"}}
                  >
                    {{icon "users"}}
                    {{lottery.participant_count}}
                  </span>
                  <span
                    class="meta-item"
                    title={{i18n "vzekc_verlosung.history.packets"}}
                  >
                    {{icon "cube"}}
                    {{lottery.packet_count}}
                  </span>
                  <span
                    class="meta-item"
                    title={{i18n "vzekc_verlosung.history.collected"}}
                  >
                    {{icon "circle-check"}}
                    {{lottery.collected_count}}/{{lottery.packet_count}}
                  </span>
                </div>
              </div>

              {{#if (includes this.expandedIds lottery.id)}}
                <div class="lottery-card-body">
                  <table class="packets-table">
                    <thead>
                      <tr>
                        <th>{{i18n "vzekc_verlosung.history.table.packet"}}</th>
                        <th>{{i18n "vzekc_verlosung.history.table.winner"}}</th>
                        <th>{{i18n
                            "vzekc_verlosung.history.table.collected"
                          }}</th>
                        <th>{{i18n
                            "vzekc_verlosung.history.table.bericht"
                          }}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {{#each lottery.packets as |packet|}}
                        <tr>
                          <td class="packet-title">{{packet.title}}</td>
                          <td class="packet-winner">
                            {{#if packet.winner}}
                              {{avatar packet.winner imageSize="tiny"}}
                              <a href="/u/{{packet.winner.username}}">
                                {{packet.winner.username}}
                              </a>
                            {{else}}
                              <span class="no-winner">-</span>
                            {{/if}}
                          </td>
                          <td class="packet-collected">
                            {{#if packet.collected_at}}
                              <span class="status-yes">{{icon "check"}}</span>
                            {{else}}
                              <span class="status-no">{{icon "xmark"}}</span>
                            {{/if}}
                          </td>
                          <td class="packet-bericht">
                            {{#if packet.erhaltungsbericht_required}}
                              {{#if packet.bericht_url}}
                                <a
                                  href={{packet.bericht_url}}
                                  class="bericht-link"
                                >{{icon "file-lines"}}</a>
                              {{else}}
                                <span class="status-no">{{icon "minus"}}</span>
                              {{/if}}
                            {{/if}}
                          </td>
                        </tr>
                      {{/each}}
                    </tbody>
                  </table>
                </div>
              {{/if}}
            </div>
          {{/each}}
        </div>

        {{#if this.hasMore}}
          <div class="load-more-container">
            <button
              type="button"
              class="btn btn-default load-more-btn"
              disabled={{this.isLoadingMore}}
              {{on "click" this.loadMore}}
            >
              {{#if this.isLoadingMore}}
                {{icon "spinner" class="fa-spin"}}
              {{else}}
                {{i18n "vzekc_verlosung.history.load_more"}}
              {{/if}}
            </button>
          </div>
        {{/if}}
      {{else}}
        <div class="no-lotteries">
          {{i18n "vzekc_verlosung.history.no_results"}}
        </div>
      {{/if}}
    </div>
  </template>
}
