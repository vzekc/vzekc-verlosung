import { i18n } from "discourse-i18n";
import ActiveLotteriesList from "../components/active-lotteries-list";
import NeueVerlosungButton from "../components/neue-verlosung-button";

<template>
  <div class="active-lotteries-page">
    <div class="active-lotteries-header">
      <h1>{{i18n "vzekc_verlosung.active.title"}}</h1>
      <NeueVerlosungButton @forceShow={{true}} />
    </div>

    <ActiveLotteriesList @lotteries={{@model.lotteries}} />
  </div>
</template>
