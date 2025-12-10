import RouteTemplate from "ember-route-template";
import UserVerlosungenStats from "../../components/user-verlosungen-stats";

export default RouteTemplate(
  <template>
    <UserVerlosungenStats
      @user={{@model.user}}
      @activeTab={{@controller.tab}}
      @onTabChange={{@controller.updateTab}}
    />
  </template>
);
