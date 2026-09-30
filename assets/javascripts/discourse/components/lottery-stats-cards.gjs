import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const CACHE_KEY = "lottery-stats";

/**
 * Displays statistics cards for lottery history
 *
 * @component LotteryStatsCards
 * @param {string} @period - Look-back period ("3m", "6m", "1y" or "all")
 */
export default class LotteryStatsCards extends Component {
  @service historyStore;

  @tracked stats = null;
  @tracked isLoading = true;

  constructor() {
    super(...arguments);
    this.loadStats();
  }

  /**
   * Cache key for the statistics of a period
   *
   * @param {string} period - Look-back period
   * @returns {string}
   */
  cacheKey(period) {
    return `${CACHE_KEY}-${period}`;
  }

  /**
   * Loads the statistics for the current period. A response for a period that is no
   * longer selected is discarded.
   */
  @action
  async loadStats() {
    const period = this.args.period;

    // Check cache first for instant restore on back navigation
    const cached = this.historyStore.get(this.cacheKey(period));
    if (cached) {
      this.stats = cached;
      this.isLoading = false;
    } else {
      this.isLoading = true;
    }

    try {
      const result = await ajax("/vzekc-verlosung/history/stats.json", {
        data: { period },
      });
      // Cache for back navigation
      this.historyStore.set(this.cacheKey(period), result);
      if (period === this.args.period) {
        this.stats = result;
      }
    } finally {
      if (period === this.args.period) {
        this.isLoading = false;
      }
    }
  }

  <template>
    <div class="lottery-stats-cards" {{didUpdate this.loadStats @period}}>
      {{#if this.isLoading}}
        <div class="stats-loading">
          {{icon "spinner" class="fa-spin"}}
        </div>
      {{else if this.stats}}
        <div class="stats-row">
          <div class="stat-card">
            <div class="stat-value">{{this.stats.total_lotteries}}</div>
            <div class="stat-label">
              {{icon "dice"}}
              {{i18n "vzekc_verlosung.history.stats.lotteries"}}
            </div>
          </div>

          <div class="stat-card">
            <div class="stat-value">{{this.stats.total_packets}}</div>
            <div class="stat-label">
              {{icon "cube"}}
              {{i18n "vzekc_verlosung.history.stats.packets"}}
            </div>
          </div>
        </div>

        <div class="stats-row">
          <div class="stat-card">
            <div class="stat-value">{{this.stats.unique_participants}}</div>
            <div class="stat-label">
              {{icon "users"}}
              {{i18n "vzekc_verlosung.history.stats.participants"}}
            </div>
          </div>

          <div class="stat-card">
            <div class="stat-value">{{this.stats.total_tickets}}</div>
            <div class="stat-label">
              {{icon "ticket"}}
              {{i18n "vzekc_verlosung.history.stats.tickets"}}
            </div>
          </div>

          <div class="stat-card">
            <div class="stat-value">{{this.stats.unique_winners}}</div>
            <div class="stat-label">
              {{icon "trophy"}}
              {{i18n "vzekc_verlosung.history.stats.winners"}}
            </div>
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
