import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

/**
 * Route for creating new lottery topics
 * Accessible at /new-lottery
 *
 * Query params:
 * - donation_id: ID of donation to link lottery to
 * - donation_title: Title from donation to pre-fill
 */
export default class NewLotteryRoute extends DiscourseRoute {
  @service siteSettings;

  queryParams = {
    donation_id: { refreshModel: false },
    donation_title: { refreshModel: false },
  };

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

  model(params) {
    return {
      donationId: params.donation_id ? parseInt(params.donation_id, 10) : null,
      donationTitle: params.donation_title || null,
    };
  }
}
