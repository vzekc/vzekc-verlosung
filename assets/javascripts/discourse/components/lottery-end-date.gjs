import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { registerDestructor } from "@ember/destroyable";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * Displays lottery end date with absolute date as main display
 * and relative time in tooltip. Shows special message when ended.
 *
 * @component LotteryEndDate
 * @param {string|Date} endsAt - The end date
 */
export default class LotteryEndDate extends Component {
  @tracked now = new Date();

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

  get endDate() {
    if (!this.args.endsAt) {
      return null;
    }
    return new Date(this.args.endsAt);
  }

  get hasEnded() {
    if (!this.endDate) {
      return false;
    }
    return this.endDate <= this.now;
  }

  /**
   * Formats the end date for the "ended" message
   *
   * @returns {string} Formatted string "Beendet am <datum> um <uhrzeit>, wartet auf Ziehung"
   */
  get endedMessage() {
    if (!this.endDate) {
      return "";
    }

    const dateStr = this.endDate.toLocaleDateString("de-DE", {
      day: "numeric",
      month: "long",
      year: "numeric",
    });

    const timeStr = this.endDate.toLocaleTimeString("de-DE", {
      hour: "2-digit",
      minute: "2-digit",
    });

    return `Beendet am ${dateStr} um ${timeStr}, wartet auf Ziehung`;
  }

  /**
   * Formats the absolute date for display
   *
   * @returns {string} Formatted date string
   */
  get absoluteDate() {
    if (!this.endDate) {
      return "";
    }

    return this.endDate.toLocaleDateString("de-DE", {
      weekday: "long",
      day: "numeric",
      month: "long",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  /**
   * Calculates relative time remaining for tooltip
   *
   * @returns {string} Relative time string
   */
  get relativeTime() {
    if (!this.endDate) {
      return "";
    }

    const diffMs = this.endDate - this.now;

    if (diffMs <= 0) {
      return i18n("vzekc_verlosung.status.ended");
    }

    const diffSeconds = Math.floor(diffMs / 1000);
    const diffMinutes = Math.floor(diffSeconds / 60);
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays > 1) {
      return i18n("vzekc_verlosung.status.days_remaining", { count: diffDays });
    } else if (diffDays === 1) {
      return i18n("vzekc_verlosung.status.one_day_remaining");
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
    <div class="lottery-date lottery-ends-at" title={{this.relativeTime}}>
      {{icon "clock"}}
      <span class="date-value">
        {{#if this.hasEnded}}
          {{this.endedMessage}}
        {{else}}
          {{this.absoluteDate}}
        {{/if}}
      </span>
    </div>
  </template>
}
