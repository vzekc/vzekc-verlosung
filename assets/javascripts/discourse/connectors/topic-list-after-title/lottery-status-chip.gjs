import Component from "@glimmer/component";
import dIcon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * Component that displays a status chip for lottery topics in topic lists.
 * Shows remaining time for active lotteries or a completion indicator for finished ones.
 *
 * @component
 * @param {Object} this.args.topic - The topic object from the topic list
 */
export default class LotteryStatusChip extends Component {
  /**
   * Whether this topic is a lottery
   *
   * @type {boolean}
   */
  get isLottery() {
    return !!this.args.topic.lottery_state;
  }

  /**
   * Whether the lottery is active and accepting tickets
   *
   * @type {boolean}
   */
  get isActive() {
    if (this.args.topic.lottery_state !== "active") {
      return false;
    }

    if (!this.args.topic.lottery_ends_at) {
      return true;
    }

    const now = new Date();
    const endsAt = new Date(this.args.topic.lottery_ends_at);
    return endsAt > now;
  }

  /**
   * Whether the lottery has ended but winners haven't been drawn yet
   *
   * @type {boolean}
   */
  get isReadyToDraw() {
    if (this.args.topic.lottery_state !== "active") {
      return false;
    }

    if (!this.args.topic.lottery_ends_at) {
      return false;
    }

    const now = new Date();
    const endsAt = new Date(this.args.topic.lottery_ends_at);
    return endsAt <= now && !this.args.topic.lottery_results;
  }

  /**
   * Whether the lottery is finished (winners have been drawn)
   *
   * @type {boolean}
   */
  get isFinished() {
    return (
      this.args.topic.lottery_state === "finished" ||
      (this.args.topic.lottery_state === "active" &&
        this.args.topic.lottery_results)
    );
  }

  /**
   * Calculate time remaining for active lottery
   *
   * @type {string | null}
   */
  get timeRemaining() {
    if (!this.isActive || !this.args.topic.lottery_ends_at) {
      return null;
    }

    const now = new Date();
    const endsAt = new Date(this.args.topic.lottery_ends_at);
    const diffMs = endsAt - now;

    if (diffMs <= 0) {
      return i18n("vzekc_verlosung.status.ending_soon");
    }

    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
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
    } else {
      return i18n("vzekc_verlosung.status.ending_soon");
    }
  }

  <template>
    {{#if this.isLottery}}
      <span class="lottery-status-chip">
        {{#if this.isActive}}
          <span class="lottery-status-chip__active">
            {{dIcon "clock"}}
            <span
              class="lottery-status-chip__text"
            >{{this.timeRemaining}}</span>
          </span>
        {{else if this.isReadyToDraw}}
          <span class="lottery-status-chip__ready-to-draw">
            {{dIcon "dice"}}
            <span class="lottery-status-chip__text">{{i18n
                "vzekc_verlosung.status.ready_to_draw"
              }}</span>
          </span>
        {{else if this.isFinished}}
          <span class="lottery-status-chip__finished">
            {{dIcon "trophy"}}
            <span class="lottery-status-chip__text">{{i18n
                "vzekc_verlosung.status.finished"
              }}</span>
          </span>
        {{/if}}
      </span>
    {{/if}}
  </template>
}
