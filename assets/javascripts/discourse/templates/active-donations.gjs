import { i18n } from "discourse-i18n";
import ActiveDonationsList from "../components/active-donations-list";
import NeueSpendeButton from "../components/neue-spende-button";

<template>
  <div class="active-donations-page">
    <div class="active-donations-header">
      <h1>{{i18n "vzekc_verlosung.active_donations.title"}}</h1>
      <div class="header-actions">
        <NeueSpendeButton @forceShow={{true}} />
      </div>
    </div>

    <ActiveDonationsList @donations={{@model.donations}} />
  </div>
</template>
