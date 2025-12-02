import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

/**
 * Route for creating new lottery topics
 * Accessible at /new-lottery
 */
export default class NewLotteryRoute extends DiscourseRoute {
  @service siteSettings;

  beforeModel() {
    // Redirect to login if not authenticated
    if (!this.currentUser) {
      this.replaceWith("login");
      return;
    }

    // Check if lottery feature is enabled
    if (!this.siteSettings.vzekc_verlosung_enabled) {
      this.replaceWith("discovery.latest");
      return;
    }

    // Get lottery category ID
    const lotteryCategoryId = parseInt(
      this.siteSettings.vzekc_verlosung_category_id,
      10
    );

    if (!lotteryCategoryId) {
      this.replaceWith("discovery.latest");
      return;
    }
  }
}
