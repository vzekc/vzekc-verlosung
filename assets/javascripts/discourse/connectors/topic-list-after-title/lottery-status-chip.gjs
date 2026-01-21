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
   * The completion status from the server
   * One of: 'active', 'ready_to_draw', 'no_tickets', 'drawn', 'finished'
   *
   * @type {string | undefined}
   */
  get completionStatus() {
    return this.args.topic.lottery_completion_status;
  }

  /**
   * Whether the lottery is active and accepting tickets
   *
   * @type {boolean}
   */
  get isActive() {
    return this.completionStatus === "active";
  }

  /**
   * Whether the lottery has ended but winners haven't been drawn yet
   *
   * @type {boolean}
   */
  get isReadyToDraw() {
    return this.completionStatus === "ready_to_draw";
  }

  /**
   * Whether the lottery ended with no participants (no tickets were bought)
   *
   * @type {boolean}
   */
  get hasNoTickets() {
    return this.completionStatus === "no_tickets";
  }

  /**
   * Whether the lottery is drawn but reports are still pending
   *
   * @type {boolean}
   */
  get isDrawn() {
    return this.completionStatus === "drawn";
  }

  /**
   * Whether the lottery is finished (drawn AND all required reports written)
   *
   * @type {boolean}
   */
  get isFinished() {
    return this.completionStatus === "finished";
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
        {{else if this.hasNoTickets}}
          <span
            class="lottery-status-chip__no-winner"
            title={{this.endDateTooltip}}
          >
            {{dIcon "ban"}}
            <span class="lottery-status-chip__text">{{i18n
                "vzekc_verlosung.status.no_winner"
              }}</span>
          </span>
        {{else if this.isDrawn}}
          <span
            class="lottery-status-chip__drawn"
            title={{this.endDateTooltip}}
          >
            {{dIcon "trophy"}}
            <span class="lottery-status-chip__text">{{i18n
                "vzekc_verlosung.status.drawn"
              }}</span>
          </span>
        {{else if this.isFinished}}
          <span
            class="lottery-status-chip__finished"
            title={{this.endDateTooltip}}
          >
            {{dIcon "circle-check"}}
            <span class="lottery-status-chip__text">{{i18n
                "vzekc_verlosung.status.finished"
              }}</span>
          </span>
        {{/if}}
      </span>
    {{/if}}
  </template>
}
