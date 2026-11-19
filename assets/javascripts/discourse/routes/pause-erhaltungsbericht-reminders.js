import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import DiscourseRoute from "discourse/routes/discourse";

/**
 * Route for pausing the Erhaltungsbericht reminders of a won packet.
 * Accessible at /erhaltungsbericht-pausieren/:post_id
 */
export default class PauseErhaltungsberichtRemindersRoute extends DiscourseRoute {
  @service router;
  @service siteSettings;

  beforeModel() {
    if (!this.currentUser) {
      this.router.replaceWith("login");
      return;
    }

    if (!this.siteSettings.vzekc_verlosung_enabled) {
      this.router.replaceWith("discovery.latest");
      return;
    }
  }

  async model(params) {
    const postId = parseInt(params.post_id, 10);

    try {
      const state = await ajax(
        `/vzekc-verlosung/packets/${postId}/erhaltungsbericht-reminders.json`
      );
      return { postId, state };
    } catch (error) {
      return { postId, error: extractError(error) };
    }
  }
}
