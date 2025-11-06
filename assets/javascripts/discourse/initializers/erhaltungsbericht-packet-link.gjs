import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

/**
 * Component to display link to packet post on Erhaltungsbericht topics
 *
 * @component ErhaltungsberichtPacketLink
 */
class ErhaltungsberichtPacketLink extends Component {
  @tracked packetUrl = null;
  @tracked packetTitle = null;
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

        // Extract packet title from post raw
        const titleMatch = post.raw.match(/^#\s+(.+)$/m);
        this.packetTitle =
          titleMatch?.[1]?.trim() || `Paket #${post.post_number}`;
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
        <div class="erhaltungsbericht-packet-notice">
          <div class="packet-notice-content">
            {{icon "box"}}
            <span class="packet-notice-text">
              {{i18n "vzekc_verlosung.erhaltungsbericht.packet_notice"}}
            </span>
            <a href={{this.packetUrl}} class="packet-link">
              {{this.packetTitle}}
            </a>
          </div>
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

      // Create container at the top of the post
      const container = document.createElement("div");
      container.className = "erhaltungsbericht-packet-link-container";
      element.insertBefore(container, element.firstChild);

      // Render component
      helper.renderGlimmer(container, ErhaltungsberichtPacketLink, {
        packetPostId,
        packetTopicId,
      });
    },
    { onlyStream: true, id: "erhaltungsbericht-packet-link" }
  );
});
