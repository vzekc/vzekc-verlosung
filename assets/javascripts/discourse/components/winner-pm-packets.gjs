import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import UserLink from "discourse/components/user-link";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import { and, eq, or } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * Component to display packet status on winner notification PMs.
 * Rendered via renderInOutlet("topic-map-expanded-after") so it
 * appears directly above the PM participant map.
 *
 * @component WinnerPmPackets
 * @param {Object} outletArgs.topic - The topic model
 */
export default class WinnerPmPackets extends Component {
  @service appEvents;
  @service packetFulfillment;

  @tracked packets = [];
  @tracked markingCollected = null;
  @tracked markingShipped = null;
  @tracked editingNotePostId = null;
  @tracked savingNote = false;

  constructor() {
    super(...arguments);
    this.packets = this.args.outletArgs?.topic?.winner_pm_packets || [];
    this.appEvents.on(
      "lottery:fulfillment-changed",
      this,
      this.onFulfillmentChanged
    );
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.appEvents.off(
      "lottery:fulfillment-changed",
      this,
      this.onFulfillmentChanged
    );
  }

  @bind
  onFulfillmentChanged(eventData) {
    if (!eventData.postId || !eventData.winners) {
      return;
    }
    const packetIndex = this.packets.findIndex(
      (p) => p.post_id === eventData.postId
    );
    if (packetIndex === -1) {
      return;
    }

    const updatedWinner = eventData.winners.find(
      (w) =>
        w.instance_number === this.packets[packetIndex].winner.instance_number
    );
    if (updatedWinner) {
      const updatedPackets = [...this.packets];
      updatedPackets[packetIndex] = {
        ...updatedPackets[packetIndex],
        winner: updatedWinner,
      };
      this.packets = updatedPackets;
    }
  }

  /**
   * Check if an action is in progress for a specific packet/instance
   *
   * @param {number} postId
   * @param {number} instanceNumber
   * @returns {boolean}
   */
  _isActionInProgress(postId, instanceNumber) {
    return (
      (this.markingCollected?.postId === postId &&
        this.markingCollected?.instanceNumber === instanceNumber) ||
      (this.markingShipped?.postId === postId &&
        this.markingShipped?.instanceNumber === instanceNumber)
    );
  }

  /**
   * Update a winner entry after a fulfillment action
   *
   * @param {number} postId
   * @param {Object} result - API response with winners array
   * @param {number} instanceNumber - the specific instance to match
   */
  _updatePacketWinner(postId, result, instanceNumber) {
    if (!result?.winners) {
      return;
    }

    const packetIndex = this.packets.findIndex((p) => p.post_id === postId);
    if (packetIndex === -1) {
      return;
    }

    const updatedWinner = result.winners.find(
      (w) => w.instance_number === instanceNumber
    );
    if (updatedWinner) {
      const updatedPackets = [...this.packets];
      updatedPackets[packetIndex] = {
        ...updatedPackets[packetIndex],
        winner: updatedWinner,
      };
      this.packets = updatedPackets;
    }

    this.appEvents.trigger("lottery:fulfillment-changed", {
      postId,
      winners: result.winners,
    });
  }

  @action
  canMarkAsShipped(packet) {
    return this.packetFulfillment.canMarkEntryAsShipped(packet.winner, {
      isLotteryOwner: true,
      isActionInProgress: this._isActionInProgress(
        packet.post_id,
        packet.winner.instance_number
      ),
    });
  }

  @action
  canMarkAsCollected(packet) {
    return this.packetFulfillment.canMarkEntryAsCollected(packet.winner, {
      isLotteryOwner: true,
      isActionInProgress: this._isActionInProgress(
        packet.post_id,
        packet.winner.instance_number
      ),
    });
  }

  @action
  async handleMarkCollected(packet) {
    const entry = packet.winner;
    if (this._isActionInProgress(packet.post_id, entry.instance_number)) {
      return;
    }

    this.markingCollected = {
      postId: packet.post_id,
      instanceNumber: entry.instance_number,
    };

    try {
      const result = await this.packetFulfillment.markEntryAsCollected(
        packet.post_id,
        entry,
        { packetTitle: packet.title }
      );
      if (result) {
        this._updatePacketWinner(packet.post_id, result, entry.instance_number);
      }
    } finally {
      this.markingCollected = null;
    }
  }

  @action
  handleMarkShipped(packet) {
    const entry = packet.winner;
    if (this._isActionInProgress(packet.post_id, entry.instance_number)) {
      return;
    }

    this.markingShipped = {
      postId: packet.post_id,
      instanceNumber: entry.instance_number,
    };

    this.packetFulfillment.markEntryAsShipped(packet.post_id, entry, {
      packetTitle: packet.title,
      onComplete: (result) => {
        if (result) {
          this._updatePacketWinner(
            packet.post_id,
            result,
            entry.instance_number
          );
        }
        this.markingShipped = null;
      },
    });
  }

  @action
  async handleMarkHandedOver(packet) {
    const entry = packet.winner;
    if (this._isActionInProgress(packet.post_id, entry.instance_number)) {
      return;
    }

    this.markingShipped = {
      postId: packet.post_id,
      instanceNumber: entry.instance_number,
    };

    try {
      const result = await this.packetFulfillment.markEntryAsHandedOver(
        packet.post_id,
        entry,
        { packetTitle: packet.title }
      );
      if (result) {
        this._updatePacketWinner(packet.post_id, result, entry.instance_number);
      }
    } finally {
      this.markingShipped = null;
    }
  }

  @action
  focusElement(element) {
    element.focus();
  }

  @action
  startEditingNote(postId) {
    this.editingNotePostId = postId;
  }

  @action
  async saveNote(packet, event) {
    const newNote = event.target.value;
    this.editingNotePostId = null;

    if (newNote === (packet.note || "")) {
      return;
    }

    this.savingNote = true;
    try {
      const result = await ajax(
        `/vzekc-verlosung/packets/${packet.post_id}/note`,
        {
          type: "PUT",
          data: { note: newNote },
        }
      );

      const packetIndex = this.packets.findIndex(
        (p) => p.post_id === packet.post_id
      );
      if (packetIndex !== -1) {
        const updatedPackets = [...this.packets];
        updatedPackets[packetIndex] = {
          ...updatedPackets[packetIndex],
          note: result.note,
        };
        this.packets = updatedPackets;
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.savingNote = false;
    }
  }

  @action
  handleNoteKeydown(packet, event) {
    if (event.key === "Escape") {
      this.editingNotePostId = null;
      event.preventDefault();
    } else if (event.key === "Enter" && !event.shiftKey) {
      event.target.blur();
      event.preventDefault();
    }
  }

  <template>
    {{#if this.packets.length}}
      <div class="winner-pm-packets">
        <h3 class="winner-pm-packets__title">
          {{icon "gift"}}
          {{i18n "vzekc_verlosung.winner_pm.packets_title"}}
        </h3>

        <ul class="winner-pm-packets__list">
          {{#each this.packets as |packet|}}
            <li class="winner-pm-packets__item">
              <div class="winner-pm-packets__packet-header">
                <span class="packet-ordinal">{{packet.ordinal}}:</span>
                <a
                  href="/t/{{packet.lottery_topic_slug}}/{{packet.lottery_topic_id}}/{{packet.post_number}}"
                  class="packet-title"
                >{{packet.title}}</a>
                <span class="packet-lottery-link">
                  (<a
                    href="/t/{{packet.lottery_topic_slug}}/{{packet.lottery_topic_id}}"
                  >{{packet.lottery_topic_title}}</a>)
                </span>
              </div>

              <div class="packet-note">
                {{#if (eq this.editingNotePostId packet.post_id)}}
                  <textarea
                    class="packet-note-input"
                    placeholder={{i18n
                      "vzekc_verlosung.packet_note.placeholder"
                    }}
                    {{didInsert this.focusElement}}
                    {{on "blur" (fn this.saveNote packet)}}
                    {{on "keydown" (fn this.handleNoteKeydown packet)}}
                  >{{packet.note}}</textarea>
                {{else}}
                  <span
                    class="packet-note-text {{unless packet.note 'empty'}}"
                    role="button"
                    {{on "click" (fn this.startEditingNote packet.post_id)}}
                  >{{if
                      packet.note
                      packet.note
                      (i18n "vzekc_verlosung.packet_note.placeholder")
                    }}</span>
                {{/if}}
              </div>

              <div class="packet-winner-row">
                <span class="packet-winner-identity">
                  <UserLink
                    @username={{packet.winner.username}}
                    class="winner-user-link"
                  >
                    {{avatar packet.winner imageSize="tiny"}}
                    <span class="winner-name">{{packet.winner.username}}</span>
                  </UserLink>
                </span>

                <span class="winner-fulfillment-status">
                  {{#if
                    (and
                      (eq packet.winner.fulfillment_state "completed")
                      packet.winner.erhaltungsbericht_topic_id
                    )
                  }}
                    <span class="status-badge status-finished">
                      {{icon "file-lines"}}
                      {{i18n "vzekc_verlosung.status.finished"}}
                    </span>
                  {{else if
                    (or
                      (eq packet.winner.fulfillment_state "received")
                      (eq packet.winner.fulfillment_state "completed")
                    )
                  }}
                    <span
                      class="status-badge status-collected"
                      title={{if
                        packet.winner.collected_at
                        (i18n
                          "vzekc_verlosung.collection.collected_on"
                          date=(this.packetFulfillment.formatCollectedDate
                            packet.winner.collected_at
                          )
                        )
                      }}
                    >
                      {{icon "check"}}
                      {{i18n "vzekc_verlosung.status.collected"}}
                    </span>
                  {{else if (eq packet.winner.fulfillment_state "shipped")}}
                    <span
                      class="status-badge status-shipped"
                      title={{if
                        packet.winner.shipped_at
                        (i18n
                          "vzekc_verlosung.shipping.shipped_on"
                          date=(this.packetFulfillment.formatCollectedDate
                            packet.winner.shipped_at
                          )
                        )
                      }}
                    >
                      {{icon "paper-plane"}}
                      {{i18n "vzekc_verlosung.status.shipped"}}
                    </span>
                  {{else}}
                    <span class="status-badge status-won">
                      {{icon "trophy"}}
                      {{i18n "vzekc_verlosung.status.won"}}
                    </span>
                  {{/if}}
                </span>

                <span class="winner-fulfillment-actions">
                  {{#if (this.canMarkAsCollected packet)}}
                    <DButton
                      @action={{fn this.handleMarkCollected packet}}
                      @icon="check"
                      @label="vzekc_verlosung.collection.received"
                      @disabled={{this.markingCollected}}
                      class="btn-small btn-default mark-collected-inline-button"
                      title={{i18n "vzekc_verlosung.collection.mark_collected"}}
                    />
                  {{else if (this.canMarkAsShipped packet)}}
                    <DButton
                      @action={{fn this.handleMarkShipped packet}}
                      @icon="paper-plane"
                      @label="vzekc_verlosung.shipping.shipped"
                      @disabled={{this.markingShipped}}
                      class="btn-small btn-default mark-shipped-inline-button"
                      title={{i18n "vzekc_verlosung.shipping.mark_shipped"}}
                    />
                    <DButton
                      @action={{fn this.handleMarkHandedOver packet}}
                      @icon="handshake"
                      @label="vzekc_verlosung.handover.handed_over"
                      @disabled={{this.markingShipped}}
                      class="btn-small btn-default mark-handed-over-inline-button"
                      title={{i18n "vzekc_verlosung.handover.mark_handed_over"}}
                    />
                  {{/if}}
                </span>

                <span class="winner-fulfillment-links">
                  {{#if packet.winner.erhaltungsbericht_topic_id}}
                    <a
                      href="/t/{{packet.winner.erhaltungsbericht_topic_id}}"
                      class="winner-bericht-link"
                      title={{i18n
                        "vzekc_verlosung.erhaltungsbericht.view_link"
                      }}
                    >{{icon "file-lines"}}</a>
                  {{/if}}
                </span>
              </div>
            </li>
          {{/each}}
        </ul>
      </div>
    {{/if}}
  </template>
}
