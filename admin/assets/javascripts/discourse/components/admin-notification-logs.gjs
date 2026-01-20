import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import avatar from "discourse/helpers/bound-avatar-template";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq } from "discourse/truth-helpers";
import I18n, { i18n } from "discourse-i18n";

/**
 * Admin component for viewing all notification logs
 *
 * @component AdminNotificationLogs
 */
export default class AdminNotificationLogs extends Component {
  @service router;

  @tracked isLoading = true;
  @tracked logs = [];
  @tracked totalCount = 0;
  @tracked page = 1;
  @tracked perPage = 50;
  @tracked notificationTypes = [];
  @tracked deliveryMethods = [];

  // Filter values
  @tracked filterUsername = "";
  @tracked filterNotificationType = "";
  @tracked filterDeliveryMethod = "";
  @tracked filterSuccess = "";

  constructor() {
    super(...arguments);
    this.loadData();
  }

  /**
   * Load notification logs from the API
   */
  async loadData() {
    this.isLoading = true;

    try {
      const params = new URLSearchParams();
      params.append("page", this.page);
      params.append("per_page", this.perPage);

      if (this.filterUsername) {
        params.append("username", this.filterUsername);
      }
      if (this.filterNotificationType) {
        params.append("notification_type", this.filterNotificationType);
      }
      if (this.filterDeliveryMethod) {
        params.append("delivery_method", this.filterDeliveryMethod);
      }
      if (this.filterSuccess !== "") {
        params.append("success", this.filterSuccess);
      }

      const result = await ajax(
        `/vzekc-verlosung/admin/notification-logs.json?${params.toString()}`
      );

      this.logs = result.notification_logs;
      this.totalCount = result.total_count;
      this.notificationTypes = result.notification_types || [];
      this.deliveryMethods = result.delivery_methods || [];
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * Apply filters and reload data
   */
  @action
  applyFilters() {
    this.page = 1;
    this.loadData();
  }

  /**
   * Clear all filters
   */
  @action
  clearFilters() {
    this.filterUsername = "";
    this.filterNotificationType = "";
    this.filterDeliveryMethod = "";
    this.filterSuccess = "";
    this.page = 1;
    this.loadData();
  }

  /**
   * Handle username filter input
   */
  @action
  updateUsername(event) {
    this.filterUsername = event.target.value;
  }

  /**
   * Handle notification type filter change
   */
  @action
  updateNotificationType(event) {
    this.filterNotificationType = event.target.value;
    this.applyFilters();
  }

  /**
   * Handle delivery method filter change
   */
  @action
  updateDeliveryMethod(event) {
    this.filterDeliveryMethod = event.target.value;
    this.applyFilters();
  }

  /**
   * Handle success filter change
   */
  @action
  updateSuccess(event) {
    this.filterSuccess = event.target.value;
    this.applyFilters();
  }

  /**
   * Handle page change
   */
  @action
  goToPage(pageNum) {
    this.page = pageNum;
    this.loadData();
  }

  /**
   * Go to previous page
   */
  @action
  prevPage() {
    if (this.page > 1) {
      this.page = this.page - 1;
      this.loadData();
    }
  }

  /**
   * Go to next page
   */
  @action
  nextPage() {
    if (this.page < this.totalPages) {
      this.page = this.page + 1;
      this.loadData();
    }
  }

  /**
   * Format date for display
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
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  /**
   * Get badge class for notification type
   */
  getTypeBadgeClass(type) {
    if (type.includes("won") || type.includes("winner")) {
      return "badge-success";
    }
    if (type.includes("reminder")) {
      return "badge-warning";
    }
    return "badge-default";
  }

  /**
   * Translate notification type to localized string
   */
  @action
  translateType(type) {
    const key = `vzekc_verlosung.admin.notification_logs.types.${type}`;
    const translated = I18n.t(key);
    // If translation not found, I18n returns the key - fall back to raw type
    return translated === key ? type : translated;
  }

  /**
   * Get total pages
   */
  get totalPages() {
    return Math.ceil(this.totalCount / this.perPage);
  }

  /**
   * Get context link for a log entry
   */
  getContextInfo(log) {
    if (log.lottery) {
      return { type: "lottery", ...log.lottery };
    }
    if (log.donation) {
      return { type: "donation", ...log.donation };
    }
    return null;
  }

  <template>
    <div class="admin-notification-logs">
      <h2>{{i18n "vzekc_verlosung.admin.notification_logs.title"}}</h2>

      <div class="notification-logs-filters">
        <div class="filter-row">
          <div class="filter-group">
            <label>{{i18n
                "vzekc_verlosung.admin.notification_logs.filters.username"
              }}</label>
            <input
              type="text"
              value={{this.filterUsername}}
              placeholder={{i18n
                "vzekc_verlosung.admin.notification_logs.filters.username_placeholder"
              }}
              {{on "input" this.updateUsername}}
              {{on "keyup" (fn this.applyFilters)}}
              class="filter-input"
            />
          </div>

          <div class="filter-group">
            <label>{{i18n
                "vzekc_verlosung.admin.notification_logs.filters.type"
              }}</label>
            <select
              class="filter-select"
              {{on "change" this.updateNotificationType}}
            >
              <option value="">{{i18n
                  "vzekc_verlosung.admin.notification_logs.filters.all"
                }}</option>
              {{#each this.notificationTypes as |type|}}
                <option
                  value={{type}}
                  selected={{eq type this.filterNotificationType}}
                >{{type}}</option>
              {{/each}}
            </select>
          </div>

          <div class="filter-group">
            <label>{{i18n
                "vzekc_verlosung.admin.notification_logs.filters.method"
              }}</label>
            <select
              class="filter-select"
              {{on "change" this.updateDeliveryMethod}}
            >
              <option value="">{{i18n
                  "vzekc_verlosung.admin.notification_logs.filters.all"
                }}</option>
              {{#each this.deliveryMethods as |method|}}
                <option
                  value={{method}}
                  selected={{eq method this.filterDeliveryMethod}}
                >{{method}}</option>
              {{/each}}
            </select>
          </div>

          <div class="filter-group">
            <label>{{i18n
                "vzekc_verlosung.admin.notification_logs.filters.status"
              }}</label>
            <select class="filter-select" {{on "change" this.updateSuccess}}>
              <option value="">{{i18n
                  "vzekc_verlosung.admin.notification_logs.filters.all"
                }}</option>
              <option
                value="true"
                selected={{eq this.filterSuccess "true"}}
              >{{i18n
                  "vzekc_verlosung.admin.notification_logs.filters.success"
                }}</option>
              <option
                value="false"
                selected={{eq this.filterSuccess "false"}}
              >{{i18n
                  "vzekc_verlosung.admin.notification_logs.filters.failed"
                }}</option>
            </select>
          </div>

          <button
            type="button"
            class="btn btn-default clear-filters"
            {{on "click" this.clearFilters}}
          >
            {{icon "times"}}
            {{i18n "vzekc_verlosung.admin.notification_logs.filters.clear"}}
          </button>
        </div>
      </div>

      {{#if this.isLoading}}
        <div class="loading-container">
          {{icon "spinner" class="fa-spin"}}
          {{i18n "loading"}}
        </div>
      {{else}}
        <div class="results-info">
          {{i18n
            "vzekc_verlosung.admin.notification_logs.results_count"
            count=this.totalCount
          }}
        </div>

        {{#if this.logs.length}}
          <table class="notification-logs-table">
            <thead>
              <tr>
                <th>{{i18n
                    "vzekc_verlosung.admin.notification_logs.table.date"
                  }}</th>
                <th>{{i18n
                    "vzekc_verlosung.admin.notification_logs.table.type"
                  }}</th>
                <th>{{i18n
                    "vzekc_verlosung.admin.notification_logs.table.method"
                  }}</th>
                <th>{{i18n
                    "vzekc_verlosung.admin.notification_logs.table.recipient"
                  }}</th>
                <th>{{i18n
                    "vzekc_verlosung.admin.notification_logs.table.context"
                  }}</th>
                <th>{{i18n
                    "vzekc_verlosung.admin.notification_logs.table.status"
                  }}</th>
              </tr>
            </thead>
            <tbody>
              {{#each this.logs as |log|}}
                <tr class={{if log.success "status-success" "status-failed"}}>
                  <td class="date-cell">{{this.formatDate log.created_at}}</td>
                  <td class="type-cell">
                    <span
                      class="notification-type-badge
                        {{this.getTypeBadgeClass log.notification_type}}"
                      title={{log.notification_type}}
                    >{{this.translateType log.notification_type}}</span>
                  </td>
                  <td class="method-cell">
                    {{#if (eq log.delivery_method "in_app")}}
                      {{icon "bell"}}
                    {{else}}
                      {{icon "envelope"}}
                    {{/if}}
                    {{log.delivery_method}}
                  </td>
                  <td class="recipient-cell">
                    {{#if log.recipient}}
                      <a
                        href="/u/{{log.recipient.username}}"
                        class="recipient-link"
                      >
                        {{avatar log.recipient.avatar_template "tiny"}}
                        <span class="username">{{log.recipient.username}}</span>
                      </a>
                    {{/if}}
                  </td>
                  <td class="context-cell">
                    {{#if log.lottery}}
                      <a href={{log.lottery.url}} class="context-link">
                        {{icon "gift"}}
                        {{log.lottery.title}}
                      </a>
                    {{else if log.donation}}
                      <a href={{log.donation.url}} class="context-link">
                        {{icon "hand-holding-heart"}}
                        {{log.donation.title}}
                      </a>
                    {{else}}
                      -
                    {{/if}}
                  </td>
                  <td class="status-cell">
                    {{#if log.success}}
                      <span class="status-icon success">{{icon "check"}}</span>
                    {{else}}
                      <span
                        class="status-icon failed"
                        title={{log.error_message}}
                      >{{icon "times"}}</span>
                    {{/if}}
                  </td>
                </tr>
                {{#unless log.success}}
                  {{#if log.error_message}}
                    <tr class="error-row">
                      <td colspan="6" class="error-message">
                        {{icon "exclamation-triangle"}}
                        {{log.error_message}}
                      </td>
                    </tr>
                  {{/if}}
                {{/unless}}
              {{/each}}
            </tbody>
          </table>

          {{#if (eq this.totalPages 1)}}
            {{! No pagination needed }}
          {{else}}
            <div class="pagination-controls">
              <button
                type="button"
                class="btn btn-default"
                disabled={{eq this.page 1}}
                {{on "click" (fn this.goToPage 1)}}
              >
                {{icon "angles-left"}}
              </button>
              <button
                type="button"
                class="btn btn-default"
                disabled={{eq this.page 1}}
                {{on "click" this.prevPage}}
              >
                {{icon "angle-left"}}
              </button>
              <span class="page-info">
                {{i18n
                  "vzekc_verlosung.admin.notification_logs.pagination.page"
                  current=this.page
                  total=this.totalPages
                }}
              </span>
              <button
                type="button"
                class="btn btn-default"
                disabled={{eq this.page this.totalPages}}
                {{on "click" this.nextPage}}
              >
                {{icon "angle-right"}}
              </button>
              <button
                type="button"
                class="btn btn-default"
                disabled={{eq this.page this.totalPages}}
                {{on "click" (fn this.goToPage this.totalPages)}}
              >
                {{icon "angles-right"}}
              </button>
            </div>
          {{/if}}
        {{else}}
          <div class="no-results">
            {{icon "bell-slash"}}
            <p>{{i18n "vzekc_verlosung.admin.notification_logs.no_results"}}</p>
          </div>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
