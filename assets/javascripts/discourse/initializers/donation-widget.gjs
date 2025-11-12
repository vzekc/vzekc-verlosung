import { apiInitializer } from "discourse/lib/api";
import DonationWidget from "../components/donation-widget";

/**
 * Initializer to decorate donation posts with the donation widget
 */
export default apiInitializer((api) => {
  api.decorateCookedElement(
    (element, helper) => {
      const post = helper.getModel();

      // Debug logging
      if (post) {
        // eslint-disable-next-line no-console
        console.log(
          `[Donation Widget] Post ${post.id}: is_donation_post=${post.is_donation_post}, donation_data=`,
          post.donation_data
        );
      }

      if (!post || !post.is_donation_post) {
        return;
      }

      // eslint-disable-next-line no-console
      console.log(`[Donation Widget] Rendering widget for post ${post.id}`);

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
