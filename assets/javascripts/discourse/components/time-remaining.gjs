import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { registerDestructor } from "@ember/destroyable";
import { i18n } from "discourse-i18n";

/**
 * Displays time remaining until a given end date, auto-updating every second
 *
 * @component TimeRemaining
 * @param {string|Date} endsAt - The end date
 */
export default class TimeRemaining extends Component {
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

  get timeRemaining() {
    const endsAt = this.args.endsAt;
    if (!endsAt) {
      return null;
    }

    const endDate = new Date(endsAt);
    // Use tracked 'now' to trigger reactivity
    const diffMs = endDate - this.now;

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

  <template>{{this.timeRemaining}}</template>
}
