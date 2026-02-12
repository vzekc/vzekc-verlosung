import UserVerlosungenStats from "../../components/user-verlosungen-stats";

<template>
  <UserVerlosungenStats
    @user={{@model.user}}
    @activeTab={{@controller.tab}}
    @onTabChange={{@controller.updateTab}}
  />
</template>
