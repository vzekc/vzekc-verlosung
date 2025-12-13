import Component from "@glimmer/component";
import { service } from "@ember/service";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";
import LotteryEndDate from "./lottery-end-date";

/**
 * Builds CSS class for username based on user roles
 *
 * @param {Object} creator - Creator object with admin/moderator flags
 * @returns {string} CSS class string
 */
function usernameClass(creator) {
  const classes = ["username"];
  if (creator.admin || creator.moderator) {
    classes.push("staff");
  }
  if (creator.admin) {
    classes.push("admin");
  }
  if (creator.moderator) {
    classes.push("moderator");
  }
  return classes.join(" ");
}

/**
 * Builds CSS class for user title based on primary group
 *
 * @param {Object} creator - Creator object with primary_group_name
 * @returns {string} CSS class string
 */
function titleClass(creator) {
  if (creator.primary_group_name) {
    return `user-title user-title--${creator.primary_group_name.toLowerCase()}`;
  }
  return "user-title";
}

/**
 * Formats a date as a short date string
 *
 * @param {string|Date} date - Date to format
 * @returns {string} Formatted date string
 */
function formatShortDate(date) {
  if (!date) {
    return "";
  }
  const d = new Date(date);
  return d.toLocaleDateString("de-DE", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

/**
 * Displays a list of active lotteries with sorting controls
 *
 * @component ActiveLotteriesList
 * @param {Array} lotteries - Array of lottery objects
 */
export default class ActiveLotteriesList extends Component {
  @service lotteryDisplayMode;

  get sortedLotteries() {
    return this.lotteryDisplayMode.sortLotteries(this.args.lotteries);
  }

  <template>
    {{#if this.sortedLotteries.length}}
      <div class="active-lotteries-list">
        {{#each this.sortedLotteries as |lottery|}}
          <div class="active-lottery-card">
            <div class="active-lottery-header">
              <h3 class="active-lottery-title">
                <a href={{lottery.url}}>{{lottery.title}}</a>
              </h3>
              <div class="active-lottery-meta">
                <div class="names trigger-user-card">
                  {{avatar lottery.creator imageSize="tiny"}}
                  <span class={{usernameClass lottery.creator}}>
                    <a
                      href="/u/{{lottery.creator.username}}/verlosungen"
                      data-user-card={{lottery.creator.username}}
                    >
                      {{lottery.creator.username}}
                      {{#if lottery.creator.moderator}}
                        <span
                          class="svg-icon-title"
                          title={{i18n "user.moderator_tooltip"}}
                        >
                          {{icon "shield-halved"}}
                        </span>
                      {{/if}}
                    </a>
                  </span>
                  {{#if lottery.creator.title}}
                    <span class={{titleClass lottery.creator}}>
                      {{lottery.creator.title}}
                    </span>
                  {{/if}}
                </div>
              </div>
            </div>

            <div class="active-lottery-info">
              <div class="active-lottery-dates">
                <div class="lottery-date lottery-created-at">
                  {{icon "far-calendar-plus"}}
                  <span class="date-value">{{formatShortDate
                      lottery.created_at
                    }}</span>
                </div>
                <LotteryEndDate @endsAt={{lottery.ends_at}} />
              </div>

              <div class="active-lottery-stats">
                <div class="stat-item">
                  {{icon "cube"}}
                  <span>{{lottery.packet_count}}
                    {{i18n "vzekc_verlosung.active.packets"}}</span>
                </div>
                <div class="stat-item">
                  {{icon "users"}}
                  <span>{{lottery.participant_count}}
                    {{i18n "vzekc_verlosung.active.participants"}}</span>
                </div>
              </div>
            </div>
          </div>
        {{/each}}
      </div>
    {{else}}
      <div class="no-active-lotteries">
        {{i18n "vzekc_verlosung.active.no_lotteries"}}
      </div>
    {{/if}}
  </template>
}
