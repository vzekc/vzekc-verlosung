import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { eq, gt } from "discourse/truth-helpers";
import I18n, { i18n } from "discourse-i18n";

/**
 * Displays lottery statistics for a user profile
 *
 * @component UserVerlosungenStats
 * @param {Object} user - The user object
 */
export default class UserVerlosungenStats extends Component {
  @tracked isLoading = true;
  @tracked stats = null;
  @tracked luck = null;
  @tracked wonPackets = [];
  @tracked lotteriesCreated = [];
  @tracked pickups = [];
  @tracked activeTab = "stats";

  constructor() {
    super(...arguments);
    this.loadData();
  }

  /**
   * Load user lottery statistics from the API
   */
  async loadData() {
    const username = this.args.user.username;

    try {
      const result = await ajax(`/vzekc-verlosung/users/${username}.json`);
      this.stats = result.stats;
      this.luck = result.luck;
      this.wonPackets = result.won_packets;
      this.lotteriesCreated = result.lotteries_created;
      this.pickups = result.pickups;
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * Switch to a different tab
   *
   * @param {String} tab - Tab identifier
   */
  @action
  switchTab(tab) {
    this.activeTab = tab;
  }

  /**
   * Get CSS class for luck value display
   *
   * @returns {String} CSS class
   */
  get luckClass() {
    if (!this.luck) {
      return "";
    }
    if (this.luck.luck > 0.5) {
      return "luck-positive";
    }
    if (this.luck.luck < -0.5) {
      return "luck-negative";
    }
    return "luck-neutral";
  }

  /**
   * Get label for luck factor
   *
   * @returns {String} Localized label
   */
  get luckLabel() {
    if (!this.luck) {
      return "";
    }
    if (this.luck.luck > 0.5) {
      return i18n("vzekc_verlosung.user_stats.glueckspilz");
    }
    if (this.luck.luck < -0.5) {
      return i18n("vzekc_verlosung.user_stats.pechvogel");
    }
    return i18n("vzekc_verlosung.user_stats.neutral");
  }

  /**
   * Get icon name for luck factor
   *
   * @returns {String} Icon name
   */
  get luckIcon() {
    if (!this.luck) {
      return "minus";
    }
    if (this.luck.luck > 0.5) {
      return "clover";
    }
    if (this.luck.luck < -0.5) {
      return "cloud-rain";
    }
    return "minus";
  }

  /**
   * Check if user has participated in any lotteries
   *
   * @returns {Boolean} True if user has participated
   */
  get hasParticipated() {
    return this.luck && this.luck.participated > 0;
  }

  /**
   * Format a date for display
   *
   * @param {String|Date} dateValue - Date to format
   * @returns {String} Formatted date
   */
  @action
  formatDate(dateValue) {
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
    <div class="user-verlosungen-stats">
      {{#if this.isLoading}}
        <div class="loading-container">
          {{icon "spinner" class="fa-spin"}}
          {{i18n "loading"}}
        </div>
      {{else}}
        <div class="stats-tabs">
          <button
            type="button"
            class="btn btn-flat {{if (eq this.activeTab 'stats') 'active'}}"
            {{on "click" (fn this.switchTab "stats")}}
          >
            {{icon "chart-bar"}}
            {{i18n "vzekc_verlosung.user_stats.tabs.stats"}}
          </button>
          <button
            type="button"
            class="btn btn-flat {{if (eq this.activeTab 'pickups') 'active'}}"
            {{on "click" (fn this.switchTab "pickups")}}
          >
            {{icon "box-archive"}}
            {{i18n "vzekc_verlosung.user_stats.tabs.pickups"}}
          </button>
          <button
            type="button"
            class="btn btn-flat {{if (eq this.activeTab 'created') 'active'}}"
            {{on "click" (fn this.switchTab "created")}}
          >
            {{icon "gift"}}
            {{i18n "vzekc_verlosung.user_stats.tabs.created"}}
          </button>
          <button
            type="button"
            class="btn btn-flat {{if (eq this.activeTab 'won') 'active'}}"
            {{on "click" (fn this.switchTab "won")}}
          >
            {{icon "trophy"}}
            {{i18n "vzekc_verlosung.user_stats.tabs.won"}}
          </button>
        </div>

        {{#if (eq this.activeTab "stats")}}
          <div class="stats-overview">
            <div class="stats-cards">
              <div class="stat-card">
                <div class="stat-icon">{{icon "dice"}}</div>
                <div class="stat-content">
                  <div class="stat-value">{{this.stats.tickets_count}}</div>
                  <div class="stat-label">{{i18n
                      "vzekc_verlosung.user_stats.tickets_drawn"
                      count=this.stats.tickets_count
                    }}</div>
                </div>
              </div>

              <div class="stat-card">
                <div class="stat-icon">{{icon "trophy"}}</div>
                <div class="stat-content">
                  <div class="stat-value">{{this.stats.packets_won}}</div>
                  <div class="stat-label">{{i18n
                      "vzekc_verlosung.user_stats.packets_won"
                      count=this.stats.packets_won
                    }}</div>
                </div>
              </div>

              <div class="stat-card">
                <div class="stat-icon">{{icon "file-lines"}}</div>
                <div class="stat-content">
                  <div class="stat-value">{{this.stats.berichte_count}}</div>
                  <div class="stat-label">{{i18n
                      "vzekc_verlosung.user_stats.berichte_written"
                      count=this.stats.berichte_count
                    }}</div>
                </div>
              </div>
            </div>

            {{#if this.hasParticipated}}
              <div class="luck-section">
                <h3>{{i18n "vzekc_verlosung.user_stats.luck_factor"}}</h3>
                <div class="luck-display {{this.luckClass}}">
                  <div class="luck-badge">
                    {{icon this.luckIcon}}
                    <span class="luck-label">{{this.luckLabel}}</span>
                  </div>
                  <div class="luck-details">
                    <div class="luck-stat">
                      <span class="luck-stat-label">{{i18n
                          "vzekc_verlosung.user_stats.participated"
                        }}</span>
                      <span
                        class="luck-stat-value"
                      >{{this.luck.participated}}</span>
                    </div>
                    <div class="luck-stat">
                      <span class="luck-stat-label">{{i18n
                          "vzekc_verlosung.user_stats.expected_wins"
                        }}</span>
                      <span
                        class="luck-stat-value"
                      >{{this.luck.expected}}</span>
                    </div>
                    <div class="luck-stat">
                      <span class="luck-stat-label">{{i18n
                          "vzekc_verlosung.user_stats.actual_wins"
                        }}</span>
                      <span class="luck-stat-value">{{this.luck.wins}}</span>
                    </div>
                    <div class="luck-stat luck-factor">
                      <span class="luck-stat-label">{{i18n
                          "vzekc_verlosung.user_stats.luck_value"
                        }}</span>
                      <span class="luck-stat-value {{this.luckClass}}">
                        {{#if (gt this.luck.luck 0)}}+{{/if}}{{this.luck.luck}}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            {{/if}}
          </div>
        {{/if}}

        {{#if (eq this.activeTab "won")}}
          <div class="won-packets-list">
            {{#if this.wonPackets.length}}
              <table class="user-verlosungen-table">
                <thead>
                  <tr>
                    <th>{{i18n "vzekc_verlosung.user_stats.table.packet"}}</th>
                    <th>{{i18n "vzekc_verlosung.user_stats.table.lottery"}}</th>
                    <th>{{i18n "vzekc_verlosung.user_stats.table.won_at"}}</th>
                    <th>{{i18n
                        "vzekc_verlosung.user_stats.table.collected"
                      }}</th>
                    <th>{{i18n "vzekc_verlosung.user_stats.table.bericht"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.wonPackets as |packet|}}
                    <tr>
                      <td>
                        <a href={{packet.url}} class="packet-link">
                          {{packet.title}}
                        </a>
                      </td>
                      <td>
                        <a href={{packet.lottery.url}} class="lottery-link">
                          {{packet.lottery.title}}
                        </a>
                      </td>
                      <td>{{this.formatDate packet.won_at}}</td>
                      <td class="status-cell">
                        {{#if packet.collected_at}}
                          <span class="status-yes">{{icon "check"}}</span>
                        {{else}}
                          <span class="status-no">{{icon "xmark"}}</span>
                        {{/if}}
                      </td>
                      <td class="status-cell">
                        {{#if packet.erhaltungsbericht_required}}
                          {{#if packet.erhaltungsbericht}}
                            <a
                              href={{packet.erhaltungsbericht.url}}
                              class="bericht-link"
                            >
                              {{icon "file-lines"}}
                            </a>
                          {{else}}
                            <span class="status-pending">{{icon "minus"}}</span>
                          {{/if}}
                        {{else}}
                          <span class="status-na">-</span>
                        {{/if}}
                      </td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            {{else}}
              <div class="empty-state">
                {{icon "trophy"}}
                <p>{{i18n "vzekc_verlosung.user_stats.no_wins"}}</p>
              </div>
            {{/if}}
          </div>
        {{/if}}

        {{#if (eq this.activeTab "created")}}
          <div class="lotteries-created-list">
            {{#if this.lotteriesCreated.length}}
              <table class="user-verlosungen-table">
                <thead>
                  <tr>
                    <th>{{i18n "vzekc_verlosung.user_stats.table.lottery"}}</th>
                    <th>{{i18n "vzekc_verlosung.user_stats.table.ended"}}</th>
                    <th>{{i18n "vzekc_verlosung.user_stats.table.packets"}}</th>
                    <th>{{i18n
                        "vzekc_verlosung.user_stats.table.participants"
                      }}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.lotteriesCreated as |lottery|}}
                    <tr>
                      <td>
                        <a href={{lottery.url}} class="lottery-link">
                          {{lottery.title}}
                        </a>
                      </td>
                      <td>{{this.formatDate lottery.ends_at}}</td>
                      <td>{{lottery.packet_count}}</td>
                      <td>{{lottery.participant_count}}</td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            {{else}}
              <div class="empty-state">
                {{icon "gift"}}
                <p>{{i18n "vzekc_verlosung.user_stats.no_lotteries"}}</p>
              </div>
            {{/if}}
          </div>
        {{/if}}

        {{#if (eq this.activeTab "pickups")}}
          <div class="pickups-list">
            {{#if this.pickups.length}}
              <table class="user-verlosungen-table">
                <thead>
                  <tr>
                    <th>{{i18n
                        "vzekc_verlosung.user_stats.table.donation"
                      }}</th>
                    <th>{{i18n
                        "vzekc_verlosung.user_stats.table.picked_up_at"
                      }}</th>
                    <th>{{i18n "vzekc_verlosung.user_stats.table.outcome"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.pickups as |pickup|}}
                    <tr>
                      <td>
                        <a href={{pickup.donation.url}} class="donation-link">
                          {{pickup.donation.title}}
                        </a>
                      </td>
                      <td>{{this.formatDate pickup.picked_up_at}}</td>
                      <td>
                        {{#if pickup.outcome}}
                          {{#if (eq pickup.outcome.type "lottery")}}
                            <a href={{pickup.outcome.url}} class="outcome-link">
                              {{icon "gift"}}
                              {{i18n
                                "vzekc_verlosung.user_stats.outcome_lottery"
                              }}
                            </a>
                          {{else}}
                            <a href={{pickup.outcome.url}} class="outcome-link">
                              {{icon "file-lines"}}
                              {{i18n
                                "vzekc_verlosung.user_stats.outcome_bericht"
                              }}
                            </a>
                          {{/if}}
                        {{else}}
                          <span class="status-pending">
                            {{icon "clock"}}
                            {{i18n
                              "vzekc_verlosung.user_stats.outcome_pending"
                            }}
                          </span>
                        {{/if}}
                      </td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            {{else}}
              <div class="empty-state">
                {{icon "box-archive"}}
                <p>{{i18n "vzekc_verlosung.user_stats.no_pickups"}}</p>
              </div>
            {{/if}}
          </div>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
