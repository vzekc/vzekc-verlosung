import { array } from "@ember/helper";
import UserVerlosungenStats from "../../components/user-verlosungen-stats";

<template>
  {{#each (array @model.user) key="id" as |user|}}
    <UserVerlosungenStats
      @user={{user}}
      @activeTab={{@controller.tab}}
      @onTabChange={{@controller.updateTab}}
    />
  {{/each}}
</template>
