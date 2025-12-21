import Component from "@glimmer/component";
import { service } from "@ember/service";
import { includes } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import LotteryCard from "./lottery-card";

/**
 * Displays a list of active lotteries with sorting controls
 *
 * @component ActiveLotteriesList
 * @param {Array} lotteries - Array of lottery objects
 * @param {Array} expandedIds - Array of expanded lottery IDs
 * @param {Function} onToggleExpanded - Callback when lottery is expanded/collapsed
 */
export default class ActiveLotteriesList extends Component {
  @service lotteryDisplayMode;

  get sortedLotteries() {
    return this.lotteryDisplayMode.sortLotteries(this.args.lotteries);
  }

  <template>
    {{#if this.sortedLotteries.length}}
      <div class="lottery-card-list">
        {{#each this.sortedLotteries as |lottery|}}
          <LotteryCard
            @lottery={{lottery}}
            @isFinished={{false}}
            @isExpanded={{includes @expandedIds lottery.id}}
            @onToggleExpanded={{@onToggleExpanded}}
          />
        {{/each}}
      </div>
    {{else}}
      <div class="no-lotteries">
        {{i18n "vzekc_verlosung.active.no_lotteries"}}
      </div>
    {{/if}}
  </template>
}
