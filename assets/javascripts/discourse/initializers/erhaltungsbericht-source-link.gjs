import { apiInitializer } from "discourse/lib/api";
import ErhaltungsberichtSourceLink from "../components/erhaltungsbericht-source-link";

export default apiInitializer((api) => {
  api.decorateCookedElement(
    (element, helper) => {
      const post = helper.getModel();
      const topic = post?.topic;

      if (!topic) {
        return;
      }

      // Only show this link on topics in the Erhaltungsberichte category
      // (not on donation/lottery topics themselves)
      const siteSettings = api.container.lookup("service:site-settings");
      const erhaltungsberichteCategoryId = parseInt(
        siteSettings.vzekc_verlosung_erhaltungsberichte_category_id,
        10
      );

      if (
        !erhaltungsberichteCategoryId ||
        topic.category_id !== erhaltungsberichteCategoryId
      ) {
        return;
      }

      // Check if this is an Erhaltungsbericht with source links
      const donationSource = topic.erhaltungsbericht_source_donation;
      const packetSource = topic.erhaltungsbericht_source_packet;

      // Must have at least one source
      if (!donationSource && !packetSource) {
        return;
      }

      // Only render once (on the first post)
      if (post.post_number !== 1) {
        return;
      }

      // Check if already rendered
      if (element.querySelector(".erhaltungsbericht-source-link")) {
        return;
      }

      // Render component
      const container = document.createElement("div");
      container.className = "erhaltungsbericht-source-container";
      element.prepend(container);

      // Pass properties directly - renderGlimmer will wrap them in 'data'
      if (donationSource) {
        helper.renderGlimmer(container, ErhaltungsberichtSourceLink, {
          donationId: donationSource.id,
          donationTopic: {
            url: donationSource.url,
            title: donationSource.title,
          },
        });
      } else if (packetSource) {
        helper.renderGlimmer(container, ErhaltungsberichtSourceLink, {
          packetUrl: packetSource.packet_url,
          lotteryTitle: packetSource.lottery_title,
        });
      }
    },
    { onlyStream: true, id: "erhaltungsbericht-source-link" }
  );
});
