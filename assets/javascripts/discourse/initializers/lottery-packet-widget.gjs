import { apiInitializer } from "discourse/lib/api";
import LotteryWidget from "../components/lottery-widget";

export default apiInitializer((api) => {
  api.decorateCookedElement(
    (element, helper) => {
      const post = helper.getModel();

      if (!post || !post.is_lottery_packet) {
        return;
      }

      // Create container for the lottery packet widget
      const container = document.createElement("div");
      container.className = "lottery-packet-widget-container";
      element.appendChild(container);

      // Render the Glimmer component with post data
      helper.renderGlimmer(container, LotteryWidget, {
        post,
      });
    },
    { onlyStream: true }
  );
});
