import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";
import AddMerchPacketButton from "../components/add-merch-packet-button";
import MerchPacketsList from "../components/merch-packets-list";

<template>
  <div class="merch-packets-page">
    <div class="merch-packets-header">
      <h1>
        {{icon "gift"}}
        {{i18n "vzekc_verlosung.merch_packets.title"}}
      </h1>
      <div class="header-actions">
        <AddMerchPacketButton @onCreated={{@controller.refreshModel}} />
      </div>
    </div>

    <MerchPacketsList
      @packets={{@model.merch_packets}}
      @onPacketShipped={{@controller.refreshModel}}
      @shipPacketId={{@controller.ship}}
    />
  </div>
</template>
