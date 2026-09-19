import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import DiscourseRoute from "discourse/routes/discourse";

/**
 * Route for writing the Erhaltungsbericht for a won packet.
 * Accessible at /erhaltungsbericht-schreiben/:post_id
 */
export default class WriteErhaltungsberichtRoute extends DiscourseRoute {
  @service router;
  @service siteSettings;

  beforeModel() {
    if (!this.currentUser) {
      this.router.replaceWith("login");
      return;
    }

    if (!this.siteSettings.vzekc_verlosung_enabled) {
      this.router.replaceWith("discovery.latest");
      return;
    }
  }

  async model(params) {
    try {
      const draft = await ajax(
        `/vzekc-verlosung/packets/${params.post_id}/erhaltungsbericht-draft.json`
      );

      return { draft, packetUrl: draft.packet_url || `/p/${params.post_id}` };
    } catch (error) {
      return { error: extractError(error), packetUrl: `/p/${params.post_id}` };
    }
  }

  afterModel(model) {
    if (model.draft?.existing_topic_url) {
      this.router.replaceWith(model.draft.existing_topic_url);
    }
  }
}
