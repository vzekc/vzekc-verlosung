import { apiInitializer } from "discourse/lib/api";
import LotteryIntroSummary from "../components/lottery-intro-summary";

export default apiInitializer((api) => {
  api.decorateCookedElement(
    (element, helper) => {
      const post = helper.getModel();

      if (!post || !post.is_lottery_intro) {
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
