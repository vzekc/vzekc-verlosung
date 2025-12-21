import { includes } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import LotteryCard from "./lottery-card";

/**
 * Displays a list of finished lotteries
 *
 * @component FinishedLotteriesList
 * @param {Array} lotteries - Array of finished lottery objects
 * @param {Array} expandedIds - Array of expanded lottery IDs
 * @param {Function} onToggleExpanded - Callback when lottery is expanded/collapsed
 */
<template>
  {{#if @lotteries.length}}
    <div class="lottery-card-list">
      {{#each @lotteries as |lottery|}}
        <LotteryCard
          @lottery={{lottery}}
          @isFinished={{true}}
          @isExpanded={{includes @expandedIds lottery.id}}
          @onToggleExpanded={{@onToggleExpanded}}
        />
      {{/each}}
    </div>
  {{else}}
    <div class="no-lotteries">
      {{i18n "vzekc_verlosung.active.no_finished_lotteries"}}
    </div>
  {{/if}}
</template>
