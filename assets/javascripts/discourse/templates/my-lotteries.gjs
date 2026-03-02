import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import icon from "discourse/helpers/d-icon";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import MyLotteriesActive from "../components/my-lotteries-active";
import MyLotteriesDashboard from "../components/my-lotteries-dashboard";

<template>
  <div class="my-lotteries-page">
    <div class="my-lotteries-header">
      <h1>
        {{icon "list-check"}}
        {{i18n "vzekc_verlosung.my_lotteries.title"}}
      </h1>
    </div>

    <ul class="nav-pills">
      <li>
        <a
          href
          class={{if (eq @controller.activeTab "active") "active"}}
          {{on "click" (fn @controller.setActiveTab "active")}}
        >
          {{i18n "vzekc_verlosung.my_lotteries.tabs.active"}}
        </a>
      </li>
      <li>
        <a
          href
          class={{if (eq @controller.activeTab "finished") "active"}}
          {{on "click" (fn @controller.setActiveTab "finished")}}
        >
          {{i18n "vzekc_verlosung.my_lotteries.tabs.finished"}}
        </a>
      </li>
    </ul>

    {{#if (eq @controller.activeTab "active")}}
      <MyLotteriesActive
        @lotteries={{@controller.activeLotteries}}
        @onDrawn={{@controller.refreshActive}}
      />
    {{else}}
      {{#if @controller.loadingFinished}}
        <div class="loading-lotteries">
          {{icon "spinner" class="spinner"}}
          {{i18n "loading"}}
        </div>
      {{else}}
        <MyLotteriesDashboard
          @lotteries={{@controller.lotteries}}
          @onFulfillmentChanged={{@controller.refreshModel}}
        />
      {{/if}}
    {{/if}}
  </div>
</template>
