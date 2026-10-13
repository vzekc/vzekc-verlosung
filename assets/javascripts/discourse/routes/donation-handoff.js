import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

/**
 * Opens a donation offer pre-filled from an email thread handed over by Herold.
 * Accessible at /spende-aus-email/:token; the token works once.
 */
export default class DonationHandoffRoute extends DiscourseRoute {
  @service router;

  /**
   * Sends anonymous visitors to the login page; the link is kept as the
   * destination.
   */
  beforeModel() {
    if (!this.currentUser) {
      this.router.replaceWith("login");
    }
  }

  /**
   * @param {Object} params - Route params
   * @returns {Object} The handoff token
   */
  model(params) {
    return { token: params.token };
  }
}
