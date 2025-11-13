import { i18n } from "discourse-i18n";
import LotteryHistoryEntry from "./lottery-history-entry";

/**
 * Displays a list of lottery history entries
 *
 * @component LotteryHistoryList
 * @param {Array} args.lotteries - Array of lottery objects
 */
const LotteryHistoryList = <template>
  <div class="lottery-history-list">
    {{#if @lotteries.length}}
      <div class="lottery-history-count">
        {{i18n "vzekc_verlosung.history.results_count" count=@lotteries.length}}
      </div>

      {{#each @lotteries as |lottery|}}
        <LotteryHistoryEntry @lottery={{lottery}} />
      {{/each}}
    {{else}}
      <div class="lottery-history-empty">
        <p>{{i18n "vzekc_verlosung.history.no_results"}}</p>
      </div>
    {{/if}}
  </div>
</template>;

export default LotteryHistoryList;
