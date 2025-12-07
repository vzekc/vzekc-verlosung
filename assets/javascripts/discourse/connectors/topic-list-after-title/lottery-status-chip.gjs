import Component from "@glimmer/component";
import dIcon from "discourse/helpers/d-icon";
import I18n, { i18n } from "discourse-i18n";
import TimeRemaining from "../../components/time-remaining";

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
   * Format the end date for tooltip display
   *
   * @type {string | null}
   */
  get endDateTooltip() {
    if (!this.args.topic.lottery_ends_at) {
      return null;
    }

    const endsAt = new Date(this.args.topic.lottery_ends_at);
    const now = new Date();
    const locale = I18n.locale || "en";

    const formattedDate = endsAt.toLocaleDateString(locale, {
      weekday: "long",
      year: "numeric",
      month: "long",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });

    if (endsAt > now) {
      return i18n("vzekc_verlosung.status.ends_at_tooltip", {
        date: formattedDate,
      });
    } else {
      return i18n("vzekc_verlosung.status.ended_at_tooltip", {
        date: formattedDate,
      });
    }
  }

  <template>
    {{#if this.isLottery}}
      <span class="lottery-status-chip">
        {{#if this.isActive}}
          <span
            class="lottery-status-chip__active"
            title={{this.endDateTooltip}}
          >
            {{dIcon "clock"}}
            <span class="lottery-status-chip__text"><TimeRemaining
                @endsAt={{@topic.lottery_ends_at}}
              /></span>
          </span>
        {{else if this.isReadyToDraw}}
          <span
            class="lottery-status-chip__ready-to-draw"
            title={{this.endDateTooltip}}
          >
            {{dIcon "dice"}}
            <span class="lottery-status-chip__text">{{i18n
                "vzekc_verlosung.status.ready_to_draw"
              }}</span>
          </span>
        {{else if this.isFinished}}
          <span
            class="lottery-status-chip__finished"
            title={{this.endDateTooltip}}
          >
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
