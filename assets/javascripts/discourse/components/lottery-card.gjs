import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { registerDestructor } from "@ember/destroyable";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import UserLink from "discourse/components/user-link";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { eq, or } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

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

const MAX_AVATARS_TO_SHOW = 5;

/**
 * Get displayed avatars for a packet (max 5)
 *
 * @param {Array} users - Array of user objects
 * @returns {Array} First 5 users
 */
function getDisplayedUsers(users) {
  return (users || []).slice(0, MAX_AVATARS_TO_SHOW);
}

/**
 * Get remaining count for a packet
 *
 * @param {Array} users - Array of user objects
 * @returns {number|null} Remaining count or null
 */
function getRemainingCount(users) {
  const remaining = (users || []).length - MAX_AVATARS_TO_SHOW;
  return remaining > 0 ? remaining : null;
}

/**
 * Unified lottery card component for both active and finished lotteries
 *
 * @component LotteryCard
 * @param {Object} lottery - Lottery object with title, url, creator, dates, packets, etc.
 * @param {boolean} isFinished - Whether this is a finished lottery
 * @param {boolean} isExpanded - Whether the packet list is expanded
 * @param {Function} onToggleExpanded - Callback when expand/collapse is clicked
 */
/**
 * Check if the current user has a ticket for a packet
 *
 * @param {Object} packet - Packet object with users array
 * @param {number} currentUserId - Current user's ID
 * @returns {boolean} True if current user has a ticket
 */
function hasCurrentUserTicket(packet, currentUserId) {
  if (!currentUserId || !packet.users) {
    return false;
  }
  return packet.users.some((user) => user.id === currentUserId);
}

export default class LotteryCard extends Component {
  @service currentUser;
  @service lotteryDisplayMode;

  @tracked now = new Date();

  _timer = null;

  constructor() {
    super(...arguments);
    if (!this.args.isFinished) {
      this._startTimer();
      registerDestructor(this, () => this._stopTimer());
    }
  }

  _startTimer() {
    this._timer = setInterval(() => {
      this.now = new Date();
    }, 1000);
  }

  _stopTimer() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
    }
  }

  @action
  toggleExpanded(event) {
    event.preventDefault();
    this.args.onToggleExpanded?.(this.args.lottery.id);
  }

  get endDate() {
    if (!this.args.lottery.ends_at) {
      return null;
    }
    return new Date(this.args.lottery.ends_at);
  }

  get hasEnded() {
    if (!this.endDate) {
      return false;
    }
    return this.endDate <= this.now;
  }

  get hasPackets() {
    return this.args.lottery.packets && this.args.lottery.packets.length > 0;
  }

  /**
   * Count of packets where current user has bought tickets
   *
   * @returns {number} Number of packets with user's tickets
   */
  get currentUserTicketCount() {
    if (!this.currentUser?.id || !this.args.lottery.packets) {
      return 0;
    }
    return this.args.lottery.packets.filter((packet) =>
      hasCurrentUserTicket(packet, this.currentUser.id)
    ).length;
  }

  /**
   * Formats the start date (created_at) for display
   *
   * @returns {string} Formatted date string
   */
  get formattedStartDate() {
    const date = this.args.lottery.created_at;
    if (!date) {
      return "";
    }
    const d = new Date(date);

    if (this.lotteryDisplayMode.isAbsoluteMode) {
      return d.toLocaleDateString("de-DE", {
        day: "numeric",
        month: "short",
        year: "numeric",
      });
    } else {
      return this._formatRelativeDate(d);
    }
  }

  /**
   * Formats the end date for display (active lotteries)
   *
   * @returns {string} Formatted date string
   */
  get formattedEndDate() {
    if (!this.endDate) {
      return "";
    }

    if (this.hasEnded) {
      return i18n("vzekc_verlosung.status.ended");
    }

    if (this.lotteryDisplayMode.isAbsoluteMode) {
      return this.endDate.toLocaleDateString("de-DE", {
        day: "numeric",
        month: "short",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      });
    } else {
      return this._formatRelativeTime(this.endDate);
    }
  }

  /**
   * Formats the drawn date for display (finished lotteries)
   *
   * @returns {string} Formatted date string
   */
  get formattedDrawnDate() {
    const date = this.args.lottery.drawn_at;
    if (!date) {
      return "";
    }
    const d = new Date(date);

    if (this.lotteryDisplayMode.isAbsoluteMode) {
      return d.toLocaleDateString("de-DE", {
        day: "numeric",
        month: "short",
        year: "numeric",
      });
    } else {
      return this._formatRelativeDate(d);
    }
  }

  /**
   * Tooltip for start date
   *
   * @returns {string} Tooltip text
   */
  get startDateTooltip() {
    const date = this.args.lottery.created_at;
    if (!date) {
      return "";
    }
    const d = new Date(date);

    if (this.lotteryDisplayMode.isAbsoluteMode) {
      return this._formatRelativeDate(d);
    } else {
      return d.toLocaleDateString("de-DE", {
        weekday: "long",
        day: "numeric",
        month: "long",
        year: "numeric",
      });
    }
  }

  /**
   * Tooltip for end date
   *
   * @returns {string} Tooltip text
   */
  get endDateTooltip() {
    if (!this.endDate) {
      return "";
    }

    if (this.lotteryDisplayMode.isAbsoluteMode) {
      return this._formatRelativeTime(this.endDate);
    } else {
      return this.endDate.toLocaleDateString("de-DE", {
        weekday: "long",
        day: "numeric",
        month: "long",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      });
    }
  }

  /**
   * Tooltip for drawn date
   *
   * @returns {string} Tooltip text
   */
  get drawnDateTooltip() {
    const date = this.args.lottery.drawn_at;
    if (!date) {
      return "";
    }
    const d = new Date(date);

    if (this.lotteryDisplayMode.isAbsoluteMode) {
      return this._formatRelativeDate(d);
    } else {
      return d.toLocaleDateString("de-DE", {
        weekday: "long",
        day: "numeric",
        month: "long",
        year: "numeric",
      });
    }
  }

  /**
   * Format a past date as relative time
   *
   * @param {Date} date - Date to format
   * @returns {string} Relative time string
   */
  _formatRelativeDate(date) {
    const diffMs = this.now - date;
    const diffSeconds = Math.floor(diffMs / 1000);
    const diffMinutes = Math.floor(diffSeconds / 60);
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays > 30) {
      return date.toLocaleDateString("de-DE", {
        day: "numeric",
        month: "short",
        year: "numeric",
      });
    } else if (diffDays >= 1) {
      return i18n("vzekc_verlosung.time.days_ago", { count: diffDays });
    } else if (diffHours >= 1) {
      return i18n("vzekc_verlosung.time.hours_ago", { count: diffHours });
    } else if (diffMinutes >= 1) {
      return i18n("vzekc_verlosung.time.minutes_ago", { count: diffMinutes });
    } else {
      return i18n("vzekc_verlosung.time.just_now");
    }
  }

  /**
   * Format remaining time until a future date
   *
   * @param {Date} date - Future date
   * @returns {string} Relative time string
   */
  _formatRelativeTime(date) {
    const diffMs = date - this.now;

    if (diffMs <= 0) {
      return i18n("vzekc_verlosung.status.ended");
    }

    const diffSeconds = Math.floor(diffMs / 1000);
    const diffMinutes = Math.floor(diffSeconds / 60);
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays >= 1) {
      const remainingHours = diffHours % 24;
      if (diffDays === 1 && remainingHours === 1) {
        return i18n("vzekc_verlosung.status.one_day_one_hour_remaining");
      } else if (diffDays === 1) {
        return i18n("vzekc_verlosung.status.one_day_hours_remaining", {
          hours: remainingHours,
        });
      } else if (remainingHours === 1) {
        return i18n("vzekc_verlosung.status.days_one_hour_remaining", {
          days: diffDays,
        });
      }
      return i18n("vzekc_verlosung.status.days_hours_remaining", {
        days: diffDays,
        hours: remainingHours,
      });
    } else if (diffHours > 1) {
      return i18n("vzekc_verlosung.status.hours_remaining", {
        count: diffHours,
      });
    } else if (diffHours === 1) {
      return i18n("vzekc_verlosung.status.one_hour_remaining");
    } else if (diffMinutes > 5) {
      return i18n("vzekc_verlosung.status.minutes_remaining", {
        count: diffMinutes,
      });
    } else if (diffMinutes >= 1) {
      const remainingSeconds = diffSeconds % 60;
      if (diffMinutes === 1 && remainingSeconds === 1) {
        return i18n("vzekc_verlosung.status.one_minute_one_second_remaining");
      } else if (diffMinutes === 1) {
        return i18n("vzekc_verlosung.status.one_minute_seconds_remaining", {
          seconds: remainingSeconds,
        });
      } else if (remainingSeconds === 1) {
        return i18n("vzekc_verlosung.status.minutes_one_second_remaining", {
          minutes: diffMinutes,
        });
      }
      return i18n("vzekc_verlosung.status.minutes_seconds_remaining", {
        minutes: diffMinutes,
        seconds: remainingSeconds,
      });
    } else if (diffSeconds > 1) {
      return i18n("vzekc_verlosung.status.seconds_remaining", {
        count: diffSeconds,
      });
    } else {
      return i18n("vzekc_verlosung.status.one_second_remaining");
    }
  }

  <template>
    <div
      class="lottery-card
        {{if @isFinished 'lottery-card--finished'}}
        {{if @isExpanded 'lottery-card--expanded'}}"
    >
      <h3 class="lottery-card__title">
        <a href={{@lottery.url}}>{{@lottery.title}}</a>
      </h3>

      <div class="lottery-card__meta">
        <div class="lottery-card__creator trigger-user-card">
          {{avatar @lottery.creator imageSize="tiny"}}
          <span class={{usernameClass @lottery.creator}}>
            <a
              href="/u/{{@lottery.creator.username}}/verlosungen"
              data-user-card={{@lottery.creator.username}}
            >
              {{@lottery.creator.username}}
              {{#if @lottery.creator.moderator}}
                <span
                  class="svg-icon-title"
                  title={{i18n "user.moderator_tooltip"}}
                >
                  {{icon "shield-halved"}}
                </span>
              {{/if}}
            </a>
          </span>
          {{#if @lottery.creator.title}}
            <span class={{titleClass @lottery.creator}}>
              {{@lottery.creator.title}}
            </span>
          {{/if}}
        </div>

        <div class="lottery-card__dates">
          <div
            class="lottery-card__date lottery-card__date--start"
            title={{this.startDateTooltip}}
          >
            {{icon "far-calendar-plus"}}
            <span class="date-value">{{this.formattedStartDate}}</span>
          </div>
          {{#if @isFinished}}
            <div
              class="lottery-card__date lottery-card__date--drawn"
              title={{this.drawnDateTooltip}}
            >
              {{icon "calendar-check"}}
              <span class="date-value">{{this.formattedDrawnDate}}</span>
            </div>
          {{else}}
            <div
              class="lottery-card__date lottery-card__date--end
                {{if this.hasEnded 'lottery-card__date--ended'}}"
              title={{this.endDateTooltip}}
            >
              {{icon "clock"}}
              <span class="date-value">{{this.formattedEndDate}}</span>
            </div>
          {{/if}}
        </div>
      </div>

      <div class="lottery-card__stats-row">
        {{#if this.hasPackets}}
          <button
            type="button"
            class="lottery-card__expand-toggle"
            aria-expanded={{if @isExpanded "true" "false"}}
            {{on "click" this.toggleExpanded}}
          >
            {{#if @isExpanded}}
              {{icon "chevron-down"}}
            {{else}}
              {{icon "chevron-right"}}
            {{/if}}
          </button>
        {{/if}}

        <div class="lottery-card__stats">
          <div class="lottery-card__stat">
            {{icon "cube"}}
            <span>{{@lottery.packet_count}}
              {{i18n "vzekc_verlosung.active.packets"}}</span>
          </div>
          <div class="lottery-card__stat">
            {{icon "users"}}
            <span>{{@lottery.participant_count}}
              {{i18n "vzekc_verlosung.active.participants"}}</span>
          </div>
          {{#if this.currentUserTicketCount}}
            <div class="lottery-card__stat lottery-card__stat--user-tickets">
              {{icon "ticket"}}
              <span>{{i18n
                  "vzekc_verlosung.active.tickets_drawn"
                  count=this.currentUserTicketCount
                }}</span>
            </div>
          {{/if}}
        </div>
      </div>

      {{#if @isExpanded}}
        <div class="lottery-card__packets">
          <table class="lottery-card__packets-table">
            <thead>
              <tr>
                <th>{{i18n "vzekc_verlosung.history.table.packet"}}</th>
                {{#if @isFinished}}
                  <th>{{i18n "vzekc_verlosung.history.table.winner"}}</th>
                  <th>{{i18n "vzekc_verlosung.donation.state.title"}}</th>
                {{else}}
                  <th>{{i18n "vzekc_verlosung.ticket.participants"}}</th>
                {{/if}}
              </tr>
            </thead>
            <tbody>
              {{#each @lottery.packets as |packet|}}
                <tr
                  class={{if
                    (hasCurrentUserTicket packet this.currentUser.id)
                    "packet-row--user-ticket"
                  }}
                >
                  <td class="packet-title">
                    <a href={{packet.url}}>{{packet.title}}</a>
                  </td>
                  {{#if @isFinished}}
                    <td class="packet-winner">
                      {{#if packet.winners.length}}
                        {{#each packet.winners as |winnerEntry|}}
                          <div class="winner-row">
                            {{avatar winnerEntry imageSize="tiny"}}
                            <a href="/u/{{winnerEntry.username}}/verlosungen">
                              {{winnerEntry.username}}
                            </a>
                          </div>
                        {{/each}}
                      {{else}}
                        <span class="no-winner">-</span>
                      {{/if}}
                    </td>
                    <td class="packet-status">
                      {{#if packet.winners.length}}
                        {{#each packet.winners as |winnerEntry|}}
                          <div class="status-row">
                            {{#if winnerEntry.bericht_url}}
                              <a
                                href={{winnerEntry.bericht_url}}
                                class="status-finished"
                              >
                                {{icon "file-lines"}}
                                {{i18n "vzekc_verlosung.status.finished"}}
                              </a>
                            {{else if
                              (or
                                (eq winnerEntry.fulfillment_state "received")
                                (eq winnerEntry.fulfillment_state "completed")
                              )
                            }}
                              <span class="status-collected">
                                {{icon "check"}}
                                {{i18n "vzekc_verlosung.status.collected"}}
                              </span>
                            {{else if
                              (eq winnerEntry.fulfillment_state "shipped")
                            }}
                              <span class="status-shipped">
                                {{icon "paper-plane"}}
                                {{i18n "vzekc_verlosung.status.shipped"}}
                              </span>
                            {{else}}
                              <span class="status-won">
                                {{icon "trophy"}}
                                {{i18n "vzekc_verlosung.status.won"}}
                              </span>
                            {{/if}}
                          </div>
                        {{/each}}
                      {{else}}
                        <span class="status-na">-</span>
                      {{/if}}
                    </td>
                  {{else}}
                    <td class="packet-participants">
                      {{#if packet.users.length}}
                        <div class="participants-avatars">
                          {{#each (getDisplayedUsers packet.users) as |user|}}
                            <UserLink
                              @username={{user.username}}
                              class="participant-avatar"
                            >
                              {{avatar user imageSize="tiny"}}
                            </UserLink>
                          {{/each}}
                          {{#if (getRemainingCount packet.users)}}
                            <span class="participants-more">
                              +{{getRemainingCount packet.users}}
                            </span>
                          {{/if}}
                        </div>
                      {{else}}
                        <span class="no-participants">
                          {{i18n "vzekc_verlosung.ticket.no_participants"}}
                        </span>
                      {{/if}}
                    </td>
                  {{/if}}
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      {{/if}}
    </div>
  </template>
}
