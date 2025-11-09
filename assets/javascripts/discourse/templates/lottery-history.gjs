import { i18n } from "discourse-i18n";
import LotteryHistoryTable from "../components/lottery-history-table";

<template>
  <div class="lottery-history-page">
    <div class="lottery-history-header">
      <h1>{{i18n "vzekc_verlosung.history.title"}}</h1>
    </div>

    {{! Flat packet table }}
    <LotteryHistoryTable @packets={{@model.packets}} />
  </div>
</template>
