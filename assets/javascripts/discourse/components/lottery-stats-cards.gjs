import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const CACHE_KEY = "lottery-stats";

/**
 * Displays statistics cards for lottery history
 *
 * @component LotteryStatsCards
 */
export default class LotteryStatsCards extends Component {
  @service historyStore;

  @tracked stats = null;
  @tracked isLoading = true;

  constructor() {
    super(...arguments);
    // Check cache first for instant restore on back navigation
    const cached = this.historyStore.get(CACHE_KEY);
    if (cached) {
      this.stats = cached;
      this.isLoading = false;
    }
    this.loadStats();
  }

  async loadStats() {
    try {
      const result = await ajax("/vzekc-verlosung/history/stats.json");
      this.stats = result;
      // Cache for back navigation
      this.historyStore.set(CACHE_KEY, result);
    } finally {
      this.isLoading = false;
    }
  }

  <template>
    <div class="lottery-stats-cards">
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
