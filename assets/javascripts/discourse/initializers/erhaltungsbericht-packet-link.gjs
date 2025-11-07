import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";

/**
 * Component to display link to packet post on Erhaltungsbericht topics
 *
 * @component ErhaltungsberichtPacketLink
 */
class ErhaltungsberichtPacketLink extends Component {
  @tracked packetUrl = null;
  @tracked lotteryUrl = null;
  @tracked packetTitle = null;
  @tracked lotteryTitle = null;
  @tracked loading = true;

  constructor() {
    super(...arguments);
    this.loadPacketInfo();
  }

  async loadPacketInfo() {
    const { packetPostId, packetTopicId } = this.args.data;

    if (!packetPostId || !packetTopicId) {
      this.loading = false;
      return;
    }

    try {
      // Fetch the topic to get slug and post
      const result = await ajax(`/t/${packetTopicId}.json`);
      const post = result.post_stream.posts.find((p) => p.id === packetPostId);

      if (post && result.slug) {
        this.packetUrl = `/t/${result.slug}/${packetTopicId}/${post.post_number}`;
        this.lotteryUrl = `/t/${result.slug}/${packetTopicId}`;
        this.lotteryTitle = result.title;

        // Extract packet title from post raw - try multiple patterns
        let packetTitle = null;

        // Try heading with #
        const headingMatch = post.raw.match(/^#\s+(.+)$/m);
        if (headingMatch) {
          packetTitle = headingMatch[1].trim();
        }

        // Try bold text at start **Paket...**
        if (!packetTitle) {
          const boldMatch = post.raw.match(/^\*\*([^*]+)\*\*/m);
          if (boldMatch) {
            packetTitle = boldMatch[1].trim();
          }
        }

        // Try first line that's not empty
        if (!packetTitle) {
          const firstLine = post.raw.split("\n").find((line) => line.trim());
          if (firstLine && firstLine.length < 100) {
            packetTitle = firstLine.trim();
          }
        }

        // Fallback to generic title
        this.packetTitle = packetTitle || `Paket #${post.post_number}`;
      }
    } catch {
      // Silently fail if packet info cannot be loaded
    } finally {
      this.loading = false;
    }
  }

  <template>
    {{#unless this.loading}}
      {{#if this.packetUrl}}
        <div class="erhaltungsbericht-packet-link">
          {{icon "box"}}
          <span>Erhaltungsbericht für
            <a
              href={{this.packetUrl}}
              class="packet-link"
            >{{this.packetTitle}}</a>
            aus
            <a
              href={{this.lotteryUrl}}
              class="lottery-link"
            >{{this.lotteryTitle}}</a></span>
        </div>
      {{/if}}
    {{/unless}}
  </template>
}

export default apiInitializer((api) => {
  api.decorateCookedElement(
    (element, helper) => {
      const topic = helper.getModel()?.topic;

      // Check if this topic has packet reference (is an Erhaltungsbericht)
      const packetPostId = topic?.packet_post_id;
      const packetTopicId = topic?.packet_topic_id;

      if (!packetPostId || !packetTopicId) {
        return;
      }

      // Only add to first post
      const post = helper.getModel();
      if (post?.post_number !== 1) {
        return;
      }

      // Remove raw link from template if it exists
      const linkPattern = /Link zum Paket:\s*https?:\/\/[^\s]+/i;
      const paragraphs = element.querySelectorAll("p");
      paragraphs.forEach((p) => {
        if (linkPattern.test(p.textContent)) {
          p.remove();
        }
      });

      // Create container at the bottom of the post
      const container = document.createElement("div");
      container.className = "erhaltungsbericht-packet-link-container";
      element.appendChild(container);

      // Render component
      helper.renderGlimmer(container, ErhaltungsberichtPacketLink, {
        packetPostId,
        packetTopicId,
      });
    },
    { onlyStream: true, id: "erhaltungsbericht-packet-link" }
  );
});
