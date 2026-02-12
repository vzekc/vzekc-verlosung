import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import avatar from "discourse/helpers/bound-avatar-template";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { eq, gt } from "discourse/truth-helpers";
import I18n, { i18n } from "discourse-i18n";

/**
 * Displays lottery statistics for a user profile
 *
 * @component UserVerlosungenStats
 * @param {Object} user - The user object
 * @param {String} activeTab - Currently active tab
 * @param {Function} onTabChange - Callback when tab changes
 */
export default class UserVerlosungenStats extends Component {
  @service currentUser;

  @tracked isLoading = true;
  @tracked stats = null;
  @tracked luck = null;
  @tracked wonPackets = [];
  @tracked lotteriesCreated = [];
  @tracked pickups = [];

  // Notification logs
  @tracked notificationLogs = [];
  @tracked notificationLogsLoading = false;
  @tracked notificationLogsPage = 1;
  @tracked notificationLogsTotalCount = 0;
  @tracked notificationLogsLoaded = false;

  constructor() {
    super(...arguments);
    this.loadData();

    // Load notifications if tab is already active on initial load
    if (this.activeTab === "notifications") {
      this.loadNotificationLogs();
    }
  }

  /**
   * Get the currently active tab
   *
   * @returns {String} Active tab identifier
   */
  get activeTab() {
    return this.args.activeTab || "stats";
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
    this.args.onTabChange?.(tab);
    // Load notification logs on first access
    if (tab === "notifications" && !this.notificationLogsLoaded) {
      this.loadNotificationLogs();
    }
  }

  /**
   * Check if current user can view notifications tab
   * Users can only view their own notifications
   *
   * @returns {Boolean} True if user can view notifications
   */
  get canViewNotifications() {
    return (
      this.currentUser &&
      (this.currentUser.id === this.args.user.id || this.currentUser.admin)
    );
  }

  /**
   * Load notification logs for the user
   */
  async loadNotificationLogs() {
    if (!this.canViewNotifications) {
      return;
    }

    this.notificationLogsLoading = true;
    const username = this.args.user.username;

    try {
      const result = await ajax(
        `/vzekc-verlosung/users/${username}/notification-logs.json?page=${this.notificationLogsPage}&per_page=50`
      );
      this.notificationLogs = result.notification_logs;
      this.notificationLogsTotalCount = result.total_count;
      this.notificationLogsLoaded = true;
    } finally {
      this.notificationLogsLoading = false;
    }
  }

  /**
   * Go to previous page of notifications
   */
  @action
  prevNotificationPage() {
    if (this.notificationLogsPage > 1) {
      this.notificationLogsPage = this.notificationLogsPage - 1;
      this.loadNotificationLogs();
    }
  }

  /**
   * Go to next page of notifications
   */
  @action
  nextNotificationPage() {
    const totalPages = Math.ceil(this.notificationLogsTotalCount / 50);
    if (this.notificationLogsPage < totalPages) {
      this.notificationLogsPage = this.notificationLogsPage + 1;
      this.loadNotificationLogs();
    }
  }

  /**
   * Get total pages for notifications
   *
   * @returns {Number} Total pages
   */
  get notificationTotalPages() {
    return Math.ceil(this.notificationLogsTotalCount / 50);
  }

  /**
   * Translate notification type to localized string
   *
   * @param {String} type - Notification type code
   * @returns {String} Translated string
   */
  @action
  translateNotificationType(type) {
    const key = `vzekc_verlosung.admin.notification_logs.types.${type}`;
    const translated = i18n(key);
    return translated === key ? type : translated;
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

  /**
   * Get icon component for fulfillment state
   *
   * @param {String} state - Fulfillment state
   * @returns {String} Icon name
   */
  @action
  fulfillmentIcon(state) {
    const icons = {
      won: "trophy",
      shipped: "truck",
      received: "box",
      completed: "circle-check",
    };
    return icons[state] || "question";
  }

  /**
   * Get localized label for fulfillment state
   *
   * @param {String} state - Fulfillment state
   * @returns {String} Localized label
   */
  @action
  fulfillmentLabel(state) {
    return i18n(`vzekc_verlosung.status.${state}`);
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
          {{#if this.canViewNotifications}}
            <button
              type="button"
              class="btn btn-flat
                {{if (eq this.activeTab 'notifications') 'active'}}"
              {{on "click" (fn this.switchTab "notifications")}}
            >
              {{icon "bell"}}
              {{i18n "vzekc_verlosung.user_stats.tabs.notifications"}}
            </button>
          {{/if}}
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
                    <th>{{i18n "vzekc_verlosung.user_stats.table.status"}}</th>
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
                        <span
                          class="fulfillment-status fulfillment-{{packet.fulfillment_state}}"
                        >
                          {{icon
                            (this.fulfillmentIcon packet.fulfillment_state)
                          }}
                          {{this.fulfillmentLabel packet.fulfillment_state}}
                        </span>
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

        {{#if (eq this.activeTab "notifications")}}
          <div class="notifications-list">
            {{#if this.notificationLogsLoading}}
              <div class="loading-container">
                {{icon "spinner" class="fa-spin"}}
                {{i18n "loading"}}
              </div>
            {{else if this.notificationLogs.length}}
              <table class="user-verlosungen-table notification-logs-table">
                <thead>
                  <tr>
                    <th>{{i18n
                        "vzekc_verlosung.user_stats.notifications.table.date"
                      }}</th>
                    <th>{{i18n
                        "vzekc_verlosung.user_stats.notifications.table.type"
                      }}</th>
                    <th>{{i18n
                        "vzekc_verlosung.user_stats.notifications.table.method"
                      }}</th>
                    <th>{{i18n
                        "vzekc_verlosung.user_stats.notifications.table.recipient"
                      }}</th>
                    <th>{{i18n
                        "vzekc_verlosung.user_stats.notifications.table.context"
                      }}</th>
                    <th>{{i18n
                        "vzekc_verlosung.user_stats.notifications.table.status"
                      }}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.notificationLogs as |entry|}}
                    <tr
                      class={{if
                        entry.success
                        "status-success"
                        "status-failed"
                      }}
                    >
                      <td>{{this.formatDate entry.created_at}}</td>
                      <td>
                        <span
                          class="notification-type-badge"
                          title={{entry.notification_type}}
                        >{{this.translateNotificationType
                            entry.notification_type
                          }}</span>
                      </td>
                      <td>
                        {{#if (eq entry.delivery_method "in_app")}}
                          {{icon "bell"}}
                        {{else}}
                          {{icon "envelope"}}
                        {{/if}}
                      </td>
                      <td>
                        {{#if entry.recipient}}
                          <a
                            href="/u/{{entry.recipient.username}}"
                            class="recipient-link"
                          >
                            {{avatar entry.recipient.avatar_template "tiny"}}
                            {{entry.recipient.username}}
                          </a>
                        {{/if}}
                      </td>
                      <td>
                        {{#if entry.lottery}}
                          <a href={{entry.lottery.url}} class="context-link">
                            {{icon "gift"}}
                            {{entry.lottery.title}}
                          </a>
                        {{else if entry.donation}}
                          <a href={{entry.donation.url}} class="context-link">
                            {{icon "hand-holding-heart"}}
                            {{entry.donation.title}}
                          </a>
                        {{else}}
                          -
                        {{/if}}
                      </td>
                      <td class="status-cell">
                        {{#if entry.success}}
                          <span class="status-yes">{{icon "check"}}</span>
                        {{else}}
                          <span
                            class="status-no"
                            title={{entry.error_message}}
                          >{{icon "times"}}</span>
                        {{/if}}
                      </td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>

              {{#if (gt this.notificationTotalPages 1)}}
                <div class="pagination-controls">
                  <button
                    type="button"
                    class="btn btn-default"
                    disabled={{eq this.notificationLogsPage 1}}
                    {{on "click" this.prevNotificationPage}}
                  >
                    {{icon "angle-left"}}
                  </button>
                  <span class="page-info">
                    {{i18n
                      "vzekc_verlosung.user_stats.notifications.pagination.page"
                      current=this.notificationLogsPage
                      total=this.notificationTotalPages
                    }}
                  </span>
                  <button
                    type="button"
                    class="btn btn-default"
                    disabled={{eq
                      this.notificationLogsPage
                      this.notificationTotalPages
                    }}
                    {{on "click" this.nextNotificationPage}}
                  >
                    {{icon "angle-right"}}
                  </button>
                </div>
              {{/if}}
            {{else}}
              <div class="empty-state">
                {{icon "bell-slash"}}
                <p>{{i18n
                    "vzekc_verlosung.user_stats.notifications.no_notifications"
                  }}</p>
              </div>
            {{/if}}
          </div>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
