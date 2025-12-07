import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import icon from "discourse/helpers/d-icon";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import LotteryHistoryLotteries from "../components/lottery-history-lotteries";
import LotteryLeaderboard from "../components/lottery-leaderboard";
import LotteryPacketLeaderboard from "../components/lottery-packet-leaderboard";
import LotteryStatsCards from "../components/lottery-stats-cards";

<template>
  <div class="lottery-history-page">
    {{! Statistics Cards - always visible }}
    <LotteryStatsCards />

    {{! Tab Navigation }}
    <div class="lottery-history-tabs">
      <nav class="nav nav-pills">
        <button
          type="button"
          class="nav-item
            {{if (eq @controller.activeTab 'leaderboard') 'active'}}"
          {{on "click" (fn @controller.setActiveTab "leaderboard")}}
        >
          {{icon "trophy"}}
          {{i18n "vzekc_verlosung.history.tabs.leaderboard"}}
        </button>
        <button
          type="button"
          class="nav-item
            {{if (eq @controller.activeTab 'lotteries') 'active'}}"
          {{on "click" (fn @controller.setActiveTab "lotteries")}}
        >
          {{icon "dice"}}
          {{i18n "vzekc_verlosung.history.tabs.lotteries"}}
        </button>
        <button
          type="button"
          class="nav-item {{if (eq @controller.activeTab 'packets') 'active'}}"
          {{on "click" (fn @controller.setActiveTab "packets")}}
        >
          {{icon "cube"}}
          {{i18n "vzekc_verlosung.history.tabs.packets"}}
        </button>
      </nav>
    </div>

    {{! Tab Content }}
    <div class="lottery-history-content">
      {{#if (eq @controller.activeTab "packets")}}
        <LotteryPacketLeaderboard />
      {{else if (eq @controller.activeTab "lotteries")}}
        <LotteryHistoryLotteries
          @expanded={{@controller.expanded}}
          @onExpandedChange={{@controller.updateExpanded}}
        />
      {{else if (eq @controller.activeTab "leaderboard")}}
        <LotteryLeaderboard />
      {{/if}}
    </div>
  </div>
</template>
