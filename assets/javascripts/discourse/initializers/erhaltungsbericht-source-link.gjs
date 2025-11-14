import { apiInitializer } from "discourse/lib/api";
import ErhaltungsberichtSourceLink from "../components/erhaltungsbericht-source-link";

export default apiInitializer((api) => {
  api.decorateCookedElement(
    (element, helper) => {
      const topic = helper.getModel()?.topic;
      if (!topic) {
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
      const post = helper.getModel();
      if (post.post_number !== 1) {
        return;
      }

      // Check if already rendered
      if (element.querySelector(".erhaltungsbericht-source-link")) {
        return;
      }

      // Prepare data for the component
      const data = {};

      if (donationSource) {
        data.donationId = donationSource.id;
        data.donationTopic = {
          url: donationSource.url,
          title: donationSource.title,
        };
      } else if (packetSource) {
        data.packetUrl = packetSource.packet_url;
        data.lotteryTitle = packetSource.lottery_title;
      }

      // Render component
      const container = document.createElement("div");
      container.className = "erhaltungsbericht-source-container";
      element.prepend(container);

      helper.renderGlimmer(container, ErhaltungsberichtSourceLink, { data });
    },
    { onlyStream: true, id: "erhaltungsbericht-source-link" }
  );
});
