import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import RouteTemplate from "ember-route-template";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import UserVerlosungenStats from "../../components/user-verlosungen-stats";

export default RouteTemplate(
  <template><UserVerlosungenStats @user={{@model.user}} /></template>
);
