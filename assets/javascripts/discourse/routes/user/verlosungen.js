import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

export default class UserVerlosungenRoute extends DiscourseRoute {
  @service store;

  templateName = "user/verlosungen";

  model() {
    const user = this.modelFor("user");
    return { user };
  }
}
