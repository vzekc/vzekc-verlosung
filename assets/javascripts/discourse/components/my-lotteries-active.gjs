import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { registerDestructor } from "@ember/destroyable";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import UserLink from "discourse/components/user-link";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { gt } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import DrawLotteryModal from "./modal/draw-lottery-modal";

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
 * Active lotteries component for the My Lotteries page.
 * Shows running lotteries with countdown, stats, and packet participants.
 *
 * @component MyLotteriesActive
 * @param {Array} lotteries - Array of active lottery objects
 * @param {Function} onDrawn - Callback after a lottery is drawn
 */
export default class MyLotteriesActive extends Component {
  @service modal;

  @tracked now = new Date();
  @tracked drawingTopicId = null;

  _timer = null;

  constructor() {
    super(...arguments);
    this._startTimer();
    registerDestructor(this, () => this._stopTimer());
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

  /**
   * Format remaining time until a future date
   *
   * @param {string} endsAt - ISO date string
   * @returns {string} Formatted countdown or status
   */
  @action
  formatTimeRemaining(endsAt) {
    if (!endsAt) {
      return "";
    }

    const endDate = new Date(endsAt);
    const diffMs = endDate - this.now;

    if (diffMs <= 0) {
      return i18n("vzekc_verlosung.my_lotteries.waiting_for_draw");
    }

    const diffSeconds = Math.floor(diffMs / 1000);
    const diffMinutes = Math.floor(diffSeconds / 60);
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays >= 1) {
      const remainingHours = diffHours % 24;
      return i18n("vzekc_verlosung.status.days_hours_remaining", {
        days: diffDays,
        hours: remainingHours,
      });
    } else if (diffHours >= 1) {
      return i18n("vzekc_verlosung.status.hours_remaining", {
        count: diffHours,
      });
    } else if (diffMinutes >= 1) {
      return i18n("vzekc_verlosung.status.minutes_remaining", {
        count: diffMinutes,
      });
    } else {
      return i18n("vzekc_verlosung.status.seconds_remaining", {
        count: diffSeconds,
      });
    }
  }

  /**
   * Check if a lottery has ended (past ends_at) but not been drawn
   *
   * @param {string} endsAt - ISO date string
   * @returns {boolean}
   */
  @action
  hasEnded(endsAt) {
    if (!endsAt) {
      return false;
    }
    return new Date(endsAt) <= this.now;
  }

  /**
   * Total ticket count across all packets
   *
   * @param {Array} packets
   * @returns {number}
   */
  @action
  totalTickets(packets) {
    return (packets || []).reduce((sum, p) => sum + (p.ticket_count || 0), 0);
  }

  /**
   * Open the draw lottery modal
   *
   * @param {Object} lottery - Lottery object
   */
  @action
  async openDrawModal(lottery) {
    this.drawingTopicId = lottery.topic_id;
    try {
      await this.modal.show(DrawLotteryModal, {
        model: {
          topicId: lottery.topic_id,
        },
      });
      this.args.onDrawn?.();
    } finally {
      this.drawingTopicId = null;
    }
  }

  <template>
    {{#if @lotteries.length}}
      {{#each @lotteries as |lottery|}}
        <div class="my-lotteries-lottery-section">
          <div class="lottery-section-header">
            <h2>
              <a
                href="/t/{{lottery.slug}}/{{lottery.topic_id}}"
              >{{lottery.title}}</a>
            </h2>
            <span class="lottery-time-remaining">
              {{this.formatTimeRemaining lottery.ends_at}}
            </span>
          </div>

          <div class="lottery-stats-line">
            <span class="lottery-stat">
              {{icon "users"}}
              {{lottery.participant_count}}
              {{i18n "vzekc_verlosung.status.participants"}}
            </span>
            <span class="lottery-stat">
              {{icon "ticket"}}
              {{this.totalTickets lottery.packets}}
              {{i18n "vzekc_verlosung.status.tickets"}}
            </span>
          </div>

          {{#if (gt lottery.packets.length 0)}}
            <div class="active-lottery-packets">
              {{#each lottery.packets as |packet|}}
                <div class="active-lottery-packet">
                  <span class="packet-title">
                    {{packet.ordinal}}.
                    {{packet.title}}
                  </span>
                  <div class="packet-participants-row">
                    {{#if (gt packet.users.length 0)}}
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
                  </div>
                </div>
              {{/each}}
            </div>
          {{/if}}

          {{#if (this.hasEnded lottery.ends_at)}}
            <div class="lottery-draw-action">
              <DButton
                @action={{fn this.openDrawModal lottery}}
                @icon="dice"
                @label="vzekc_verlosung.drawing.draw_button"
                class="btn-primary"
              />
            </div>
          {{/if}}
        </div>
      {{/each}}
    {{else}}
      <div class="my-lotteries-empty">
        {{icon "check-circle"}}
        <p>{{i18n "vzekc_verlosung.my_lotteries.no_active_lotteries"}}</p>
      </div>
    {{/if}}
  </template>
}
