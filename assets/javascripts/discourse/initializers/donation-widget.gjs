import { apiInitializer } from "discourse/lib/api";
import DonationWidget from "../components/donation-widget";

/**
 * Initializer to decorate donation posts with the donation widget
 */
export default apiInitializer((api) => {
  api.decorateCookedElement(
    (element, helper) => {
      const post = helper.getModel();

      if (!post || !post.is_donation_post) {
        return;
      }

      // Create container for the donation widget
      const container = document.createElement("div");
      container.className = "donation-widget-container";
      element.appendChild(container);

      // Render the Glimmer component with post data
      helper.renderGlimmer(container, DonationWidget, {
        post,
      });
    },
    { onlyStream: true }
  );
});
