import Component from "@glimmer/component";
import { action } from "@ember/object";
import { schedule } from "@ember/runloop";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";

/**
 * Landing page for the direct "write your Erhaltungsbericht" link in reminder
 * PMs. Opens the prefilled composer on arrival and keeps the packet in reach
 * for a winner who closes it.
 *
 * @component WriteErhaltungsberichtPage
 * @param {Object} model - Route model
 * @param {Object} model.draft - Composer payload for the packet
 * @param {string} model.packetUrl - URL of the packet post
 * @param {string} model.error - Message explaining why no report can be written
 */
export default class WriteErhaltungsberichtPage extends Component {
  @service packetFulfillment;

  constructor() {
    super(...arguments);

    if (this.draft) {
      schedule("afterRender", this, this.openComposer);
    }
  }

  /**
   * @type {Object|null}
   */
  get draft() {
    const draft = this.args.model?.draft;
    return draft?.existing_topic_url ? null : draft;
  }

  /**
   * @returns {string}
   */
  get packetLabel() {
    const draft = this.draft;

    if (!draft) {
      return "";
    }

    return draft.packet_title
      ? `${draft.packet_title} — ${draft.lottery_title}`
      : draft.lottery_title;
  }

  @action
  openComposer() {
    const draft = this.draft;

    this.packetFulfillment.openErhaltungsberichtComposer({
      categoryId: draft.category_id,
      title: draft.title,
      template: draft.template,
      packetPostId: draft.packet_post_id,
      packetTopicId: draft.packet_topic_id,
      instanceNumber: draft.instance_number,
    });
  }

  @action
  goToPacket() {
    DiscourseURL.routeTo(this.args.model.packetUrl);
  }

  <template>
    <div class="write-erhaltungsbericht-page">
      <h2>{{i18n "vzekc_verlosung.write_erhaltungsbericht.title"}}</h2>

      {{#if @model.error}}
        <div class="alert alert-error">{{@model.error}}</div>
      {{else if this.draft}}
        <p class="packet-label"><strong>{{this.packetLabel}}</strong></p>
        <p>{{i18n "vzekc_verlosung.write_erhaltungsbericht.description"}}</p>
      {{/if}}

      <div class="write-erhaltungsbericht-actions">
        {{#if this.draft}}
          <DButton
            @action={{this.openComposer}}
            @label="vzekc_verlosung.erhaltungsbericht.create_button"
            class="btn-primary"
          />
        {{/if}}
        <DButton
          @action={{this.goToPacket}}
          @label="vzekc_verlosung.write_erhaltungsbericht.packet_button"
          class="btn-default"
        />
      </div>
    </div>
  </template>
}
