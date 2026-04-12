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
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * Dashboard component showing pending fulfillment for lottery owners.
 * Groups pending winner entries by lottery and winner.
 *
 * @component MyLotteriesDashboard
 * @param {Array} lotteries - Array of lottery objects with winner_groups
 * @param {Function} onFulfillmentChanged - Callback to refresh model
 */
export default class MyLotteriesDashboard extends Component {
  @service appEvents;
  @service packetFulfillment;

  @tracked actionInProgress = null;
  @tracked editingNoteKey = null;
  @tracked savingNote = false;

  /**
   * Check if an action is in progress for a specific entry
   *
   * @param {number} postId
   * @param {number} instanceNumber
   * @returns {boolean}
   */
  _isActionInProgress(postId, instanceNumber) {
    return (
      this.actionInProgress?.postId === postId &&
      this.actionInProgress?.instanceNumber === instanceNumber
    );
  }

  /**
   * Format ISO date string for display
   *
   * @param {string} dateStr
   * @returns {string}
   */
  _formatDate(dateStr) {
    if (!dateStr) {
      return "";
    }
    const date = new Date(dateStr);
    return date.toLocaleDateString(undefined, {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  }

  @action
  formatDrawnDate(dateStr) {
    return this._formatDate(dateStr);
  }

  @action
  canMarkAsShipped(entry) {
    return this.packetFulfillment.canMarkEntryAsShipped(entry, {
      isLotteryOwner: true,
      isActionInProgress: this._isActionInProgress(
        entry.post_id,
        entry.instance_number
      ),
    });
  }

  @action
  canMarkAsUnclaimed(entry, drawnAt) {
    return this.packetFulfillment.canMarkEntryAsUnclaimed(entry, {
      isLotteryOwner: true,
      isActionInProgress: this._isActionInProgress(
        entry.post_id,
        entry.instance_number
      ),
      drawnAt,
    });
  }

  @action
  canMarkAsCollected(entry) {
    return this.packetFulfillment.canMarkEntryAsCollected(entry, {
      isLotteryOwner: true,
      isActionInProgress: this._isActionInProgress(
        entry.post_id,
        entry.instance_number
      ),
    });
  }

  @action
  async handleMarkShipped(entry) {
    if (this._isActionInProgress(entry.post_id, entry.instance_number)) {
      return;
    }

    this.actionInProgress = {
      postId: entry.post_id,
      instanceNumber: entry.instance_number,
    };

    this.packetFulfillment.markEntryAsShipped(entry.post_id, entry, {
      packetTitle: entry.title,
      onComplete: (result) => {
        if (result) {
          this.appEvents.trigger("lottery:fulfillment-changed", {
            postId: entry.post_id,
            winners: result.winners,
          });
          this.args.onFulfillmentChanged?.();
        }
        this.actionInProgress = null;
      },
    });
  }

  @action
  async handleMarkCollected(entry) {
    if (this._isActionInProgress(entry.post_id, entry.instance_number)) {
      return;
    }

    this.actionInProgress = {
      postId: entry.post_id,
      instanceNumber: entry.instance_number,
    };

    try {
      const result = await this.packetFulfillment.markEntryAsCollected(
        entry.post_id,
        entry,
        { packetTitle: entry.title }
      );
      if (result) {
        this.appEvents.trigger("lottery:fulfillment-changed", {
          postId: entry.post_id,
          winners: result.winners,
        });
        this.args.onFulfillmentChanged?.();
      }
    } finally {
      this.actionInProgress = null;
    }
  }

  @action
  async handleMarkHandedOver(entry) {
    if (this._isActionInProgress(entry.post_id, entry.instance_number)) {
      return;
    }

    this.actionInProgress = {
      postId: entry.post_id,
      instanceNumber: entry.instance_number,
    };

    try {
      const result = await this.packetFulfillment.markEntryAsHandedOver(
        entry.post_id,
        entry,
        { packetTitle: entry.title }
      );
      if (result) {
        this.appEvents.trigger("lottery:fulfillment-changed", {
          postId: entry.post_id,
          winners: result.winners,
        });
        this.args.onFulfillmentChanged?.();
      }
    } finally {
      this.actionInProgress = null;
    }
  }

  @action
  async handleMarkUnclaimed(entry) {
    if (this._isActionInProgress(entry.post_id, entry.instance_number)) {
      return;
    }

    this.actionInProgress = {
      postId: entry.post_id,
      instanceNumber: entry.instance_number,
    };

    try {
      const result = await this.packetFulfillment.markEntryAsUnclaimed(
        entry.post_id,
        entry,
        { packetTitle: entry.title }
      );
      if (result) {
        this.appEvents.trigger("lottery:fulfillment-changed", {
          postId: entry.post_id,
          winners: result.winners,
        });
        this.args.onFulfillmentChanged?.();
      }
    } finally {
      this.actionInProgress = null;
    }
  }

  @action
  noteKey(entry) {
    return `${entry.post_id}_${entry.instance_number}`;
  }

  @action
  startEditingNote(key) {
    this.editingNoteKey = key;
  }

  @action
  focusElement(element) {
    element.focus();
  }

  @action
  async saveNote(entry, event) {
    const newNote = event.target.value;
    this.editingNoteKey = null;

    if (newNote === (entry.note || "")) {
      return;
    }

    this.savingNote = true;
    try {
      await ajax(`/vzekc-verlosung/packets/${entry.post_id}/note`, {
        type: "PUT",
        data: { note: newNote, instance_number: entry.instance_number },
      });
      this.args.onFulfillmentChanged?.();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.savingNote = false;
    }
  }

  @action
  handleNoteKeydown(entry, event) {
    if (event.key === "Escape") {
      this.editingNoteKey = null;
      event.preventDefault();
    } else if (event.key === "Enter" && !event.shiftKey) {
      event.target.blur();
      event.preventDefault();
    }
  }

  <template>
    {{#if @lotteries.length}}
      {{#each @lotteries as |lottery|}}
        <div class="my-lotteries-lottery-section">
          <div class="lottery-section-header">
            <h2>
              <a
                href="/t/{{lottery.topic_slug}}/{{lottery.topic_id}}"
              >{{lottery.topic_title}}</a>
            </h2>
            <span class="lottery-drawn-date">
              {{i18n
                "vzekc_verlosung.my_lotteries.drawn_on"
                date=(this.formatDrawnDate lottery.drawn_at)
              }}
            </span>
          </div>

          {{#each lottery.winner_groups as |group|}}
            <div class="winner-group">
              <div class="winner-group-header">
                <UserLink @username={{group.user.username}}>
                  {{avatar group.user imageSize="small"}}
                  <span class="winner-username">{{group.user.username}}</span>
                </UserLink>
                {{#if group.winner_pm_topic_id}}
                  <a
                    href="/t/{{group.winner_pm_topic_id}}"
                    class="winner-pm-link"
                    title={{i18n "vzekc_verlosung.my_lotteries.winner_pm"}}
                  >
                    {{icon "envelope"}}
                  </a>
                {{/if}}
              </div>

              <ul class="packet-entry-list">
                {{#each group.entries as |entry|}}
                  <li class="packet-entry">
                    <div class="packet-entry__title">
                      <a
                        href="/p/{{entry.post_id}}"
                        class="packet-link"
                      >{{entry.ordinal}}.
                        {{entry.title}}</a>
                      {{#if (eq entry.quantity 1)}}{{else}}
                        <span
                          class="instance-number"
                        >(#{{entry.instance_number}})</span>
                      {{/if}}
                    </div>

                    <div class="packet-entry__note">
                      {{#if (eq this.editingNoteKey (this.noteKey entry))}}
                        <textarea
                          class="packet-note-input"
                          placeholder={{i18n
                            "vzekc_verlosung.packet_note.placeholder"
                          }}
                          {{didInsert this.focusElement}}
                          {{on "blur" (fn this.saveNote entry)}}
                          {{on "keydown" (fn this.handleNoteKeydown entry)}}
                        >{{entry.note}}</textarea>
                      {{else}}
                        <span
                          class="packet-note-text {{unless entry.note 'empty'}}"
                          role="button"
                          {{on
                            "click"
                            (fn this.startEditingNote (this.noteKey entry))
                          }}
                        >{{if
                            entry.note
                            entry.note
                            (i18n "vzekc_verlosung.packet_note.placeholder")
                          }}</span>
                      {{/if}}
                    </div>

                    <div class="packet-entry__status-row">
                      <span class="packet-entry__status-left">
                        <span
                          class="fulfillment-status fulfillment-{{entry.fulfillment_state}}"
                        >
                          {{#if (eq entry.fulfillment_state "unclaimed")}}
                            {{icon "ban"}}
                            {{i18n "vzekc_verlosung.status.unclaimed"}}
                          {{else if (eq entry.fulfillment_state "shipped")}}
                            {{icon "paper-plane"}}
                            {{i18n "vzekc_verlosung.status.shipped"}}
                          {{else if (eq entry.fulfillment_state "received")}}
                            {{icon "check"}}
                            {{i18n "vzekc_verlosung.status.received"}}
                          {{else}}
                            {{icon "trophy"}}
                            {{i18n "vzekc_verlosung.status.won"}}
                          {{/if}}
                        </span>
                        {{#if entry.tracking_info}}
                          <span class="tracking-info">
                            {{entry.tracking_info}}
                          </span>
                        {{/if}}
                        {{#if entry.erhaltungsbericht_topic_id}}
                          <a
                            href="/t/{{entry.erhaltungsbericht_topic_id}}"
                            class="bericht-link"
                            title={{i18n
                              "vzekc_verlosung.erhaltungsbericht.view_link"
                            }}
                          >
                            {{icon "file-lines"}}
                          </a>
                        {{else if entry.erhaltungsbericht_required}}
                          <span class="bericht-pending">
                            {{icon "clock"}}
                          </span>
                        {{/if}}
                      </span>

                      <span class="packet-entry__actions">
                        {{#if (this.canMarkAsCollected entry)}}
                          <DButton
                            @action={{fn this.handleMarkCollected entry}}
                            @icon="check"
                            @label="vzekc_verlosung.collection.received"
                            @disabled={{this.actionInProgress}}
                            class="btn-small btn-default mark-collected-inline-button"
                          />
                        {{/if}}
                        {{#if (this.canMarkAsShipped entry)}}
                          <DButton
                            @action={{fn this.handleMarkShipped entry}}
                            @icon="paper-plane"
                            @label="vzekc_verlosung.shipping.shipped"
                            @disabled={{this.actionInProgress}}
                            class="btn-small btn-default mark-shipped-inline-button"
                          />
                          <DButton
                            @action={{fn this.handleMarkHandedOver entry}}
                            @icon="handshake"
                            @label="vzekc_verlosung.handover.handed_over"
                            @disabled={{this.actionInProgress}}
                            class="btn-small btn-default mark-handed-over-inline-button"
                          />
                        {{/if}}
                        {{#if (this.canMarkAsUnclaimed entry lottery.drawn_at)}}
                          <DButton
                            @action={{fn this.handleMarkUnclaimed entry}}
                            @icon="ban"
                            @label="vzekc_verlosung.status.unclaimed"
                            @disabled={{this.actionInProgress}}
                            class="btn-small btn-danger mark-unclaimed-inline-button"
                            title={{i18n
                              "vzekc_verlosung.unclaimed.mark_unclaimed"
                            }}
                          />
                        {{/if}}
                      </span>
                    </div>
                  </li>
                {{/each}}
              </ul>
            </div>
          {{/each}}
        </div>
      {{/each}}
    {{else}}
      <div class="my-lotteries-empty">
        {{icon "check-circle"}}
        <p>{{i18n "vzekc_verlosung.my_lotteries.no_open_lotteries"}}</p>
      </div>
    {{/if}}
  </template>
}
