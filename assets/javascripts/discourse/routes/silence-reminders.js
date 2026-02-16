import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

/**
 * Route for silencing owner reminders for a lottery
 * Accessible at /silence-reminders/:topic_id
 */
export default class SilenceRemindersRoute extends DiscourseRoute {
  @service siteSettings;

  beforeModel() {
    if (!this.currentUser) {
      this.replaceWith("login");
      return;
    }

    if (!this.siteSettings.vzekc_verlosung_enabled) {
      this.replaceWith("discovery.latest");
      return;
    }
  }

  model(params) {
    return {
      topicId: parseInt(params.topic_id, 10),
    };
  }
}
