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
      const donationId = topic.erhaltungsbericht_donation_id;
      const packetPostId = topic.packet_post_id;
      const packetTopicId = topic.packet_topic_id;

      // Must have at least one source
      if (!donationId && !packetPostId) {
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

      if (donationId) {
        // Fetch donation data from our API
        fetch(`/vzekc-verlosung/donations/${donationId}`)
          .then((response) => response.json())
          .then((donationData) => {
            if (donationData.topic_id) {
              // Fetch topic data
              fetch(`/t/${donationData.topic_id}.json`)
                .then((response) => response.json())
                .then((topicData) => {
                  data.donationId = donationId;
                  data.donationTopic = {
                    url: `/t/${topicData.slug}/${topicData.id}`,
                    title: topicData.title,
                  };

                  // Render component
                  const container = document.createElement("div");
                  container.className = "erhaltungsbericht-source-container";
                  element.prepend(container);

                  helper.renderGlimmer(
                    container,
                    ErhaltungsberichtSourceLink,
                    { data }
                  );
                })
                .catch((error) => {
                  console.error("Failed to fetch donation topic:", error);
                });
            }
          })
          .catch((error) => {
            console.error("Failed to fetch donation data:", error);
          });
      } else if (packetPostId && packetTopicId) {
        // Fetch lottery topic data
        fetch(`/t/${packetTopicId}.json`)
          .then((response) => response.json())
          .then((topicData) => {
            data.packetPostId = packetPostId;
            data.packetTopicId = packetTopicId;
            data.packetUrl = `/t/${topicData.slug}/${topicData.id}/${packetPostId}`;
            data.lotteryTitle = topicData.title;

            // Render component
            const container = document.createElement("div");
            container.className = "erhaltungsbericht-source-container";
            element.prepend(container);

            helper.renderGlimmer(container, ErhaltungsberichtSourceLink, {
              data,
            });
          })
          .catch((error) => {
            console.error("Failed to fetch lottery topic:", error);
          });
      }
    },
    { onlyStream: true, id: "erhaltungsbericht-source-link" }
  );
});
