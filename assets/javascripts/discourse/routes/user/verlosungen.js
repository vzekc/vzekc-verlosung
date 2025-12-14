import DiscourseRoute from "discourse/routes/discourse";

export default class UserVerlosungenRoute extends DiscourseRoute {
  templateName = "user/verlosungen";

  model() {
    const user = this.modelFor("user");
    return { user };
  }
}
