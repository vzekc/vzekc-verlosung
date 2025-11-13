import Component from "@glimmer/component";
import DButton from "discourse/components/d-button";

/**
 * Adds a link to lottery history page when viewing a lottery topic
 */
export default class LotteryHistoryLink extends Component {

  get shouldDisplay() {
    const topic = this.args.outletArgs?.topic;
    if (!topic) {
      return false;
    }

    // Only show on finished lotteries
    return topic.lottery_state === "finished";
  }

  <template>
    {{#if this.shouldDisplay}}
      <div class="lottery-history-link-banner">
        <DButton
          @route="lotteryHistory"
          @label="vzekc_verlosung.history.view_all_lotteries"
          @icon="list"
          class="btn-default lottery-history-link-btn"
        />
      </div>
    {{/if}}
  </template>
}
