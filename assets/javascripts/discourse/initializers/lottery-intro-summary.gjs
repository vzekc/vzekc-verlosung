import { apiInitializer } from "discourse/lib/api";
import LotteryIntroSummary from "../components/lottery-intro-summary";

export default apiInitializer((api) => {
  api.decorateCookedElement(
    (element, helper) => {
      const post = helper.getModel();

      // Only show lottery intro summary if:
      // 1. Post is a lottery intro
      // 2. Post is NOT a donation (donations have their own widget)
      if (!post || !post.is_lottery_intro || post.is_donation_post) {
        return;
      }

      // Create container for the lottery intro summary
      const container = document.createElement("div");
      container.className = "lottery-intro-summary-container";
      element.appendChild(container);

      // Render the Glimmer component with post data
      helper.renderGlimmer(container, LotteryIntroSummary, {
        post,
      });
    },
    { onlyStream: true }
  );
});
