import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import icon from "discourse/helpers/d-icon";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import ActiveLotteriesList from "../components/active-lotteries-list";
import FinishedLotteriesList from "../components/finished-lotteries-list";
import LotteryDisplayModeToggle from "../components/lottery-display-mode-toggle";
import NeueVerlosungButton from "../components/neue-verlosung-button";

<template>
  <div class="active-lotteries-page">
    <div class="active-lotteries-header">
      <h1>{{i18n "vzekc_verlosung.active.title"}}</h1>
      <div class="header-actions">
        <NeueVerlosungButton @forceShow={{true}} />
      </div>
    </div>

    <ul class="nav-pills">
      <li>
        <a
          href
          class={{if (eq @controller.activeTab "active") "active"}}
          {{on "click" (fn @controller.setActiveTab "active")}}
        >
          {{i18n "vzekc_verlosung.active.tabs.active"}}
        </a>
      </li>
      <li>
        <a
          href
          class={{if (eq @controller.activeTab "finished") "active"}}
          {{on "click" (fn @controller.setActiveTab "finished")}}
        >
          {{i18n "vzekc_verlosung.active.tabs.finished"}}
        </a>
      </li>
    </ul>

    {{#if (eq @controller.activeTab "active")}}
      <div class="active-tab-controls">
        <LotteryDisplayModeToggle />
      </div>
      <ActiveLotteriesList
        @lotteries={{@model.lotteries}}
        @expandedIds={{@controller.expandedIds}}
        @onToggleExpanded={{@controller.toggleExpanded}}
      />
    {{else}}
      {{#if @controller.loadingFinished}}
        <div class="loading-lotteries">
          {{icon "spinner" class="spinner"}}
          {{i18n "loading"}}
        </div>
      {{else}}
        <FinishedLotteriesList
          @lotteries={{@controller.finishedLotteries}}
          @expandedIds={{@controller.expandedIds}}
          @onToggleExpanded={{@controller.toggleExpanded}}
        />
      {{/if}}
    {{/if}}
  </div>
</template>
