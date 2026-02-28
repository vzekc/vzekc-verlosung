import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";
import MyLotteriesDashboard from "../components/my-lotteries-dashboard";

<template>
  <div class="my-lotteries-page">
    <div class="my-lotteries-header">
      <h1>
        {{icon "list-check"}}
        {{i18n "vzekc_verlosung.my_lotteries.title"}}
      </h1>
    </div>

    <MyLotteriesDashboard
      @lotteries={{@model.lotteries}}
      @onFulfillmentChanged={{@controller.refreshModel}}
    />
  </div>
</template>
