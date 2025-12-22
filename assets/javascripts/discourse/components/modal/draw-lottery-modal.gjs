import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, get } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { and, eq, gt, not } from "truth-helpers";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import { Lottery } from "../../lib/lottery";

/**
 * Modal component for drawing lottery winners
 *
 * @component DrawLotteryModal
 * Uses lottery.js to perform deterministic drawing and submits results to backend
 *
 * @param {Object} model.topicId - The topic ID of the lottery
 */
export default class DrawLotteryModal extends Component {
  @tracked loading = true;
  @tracked drawing = false;
  @tracked drawn = false;
  @tracked error = null;
  @tracked lotteryData = null;
  @tracked results = null;
  @tracked manualSelections = {}; // { post_id: [user_id_1, user_id_2, ...] for quantity }
  @tracked showConfirmation = false;

  constructor() {
    super(...arguments);
    this.loadDrawingData();
  }

  /**
   * Check if this is a manual drawing lottery
   */
  get isManualMode() {
    return this.lotteryData?.drawing_mode === "manual";
  }

  /**
   * Get packets that have participants (for manual mode)
   */
  get packetsWithParticipants() {
    if (!this.lotteryData?.packets) {
      return [];
    }
    return this.lotteryData.packets.filter((p) => p.participants.length > 0);
  }

  /**
   * Check if all required selections are made for manual mode
   * For multi-instance packets, all instances must have unique selections
   */
  get hasAllSelections() {
    return this.packetsWithParticipants.every((packet) => {
      const selections = this.manualSelections[packet.id] || [];
      const quantity = packet.quantity || 1;
      // Must have exactly as many selections as instances (or available participants, whichever is less)
      const requiredCount = Math.min(quantity, packet.participants.length);
      return (
        selections.length === requiredCount &&
        selections.every((s) => s && s !== "")
      );
    });
  }

  /**
   * Get selections summary for confirmation (manual mode)
   * Returns flat list of all selections with instance numbers for multi-instance
   */
  get selectionsSummary() {
    const summary = [];
    this.packetsWithParticipants.forEach((packet) => {
      const selections = this.manualSelections[packet.id] || [];
      const quantity = packet.quantity || 1;
      selections.forEach((selectedUserId, idx) => {
        const selectedParticipant = packet.participants?.find(
          (p) => p.id.toString() === selectedUserId
        );
        summary.push({
          packetTitle:
            quantity > 1 ? `${packet.title} #${idx + 1}` : packet.title,
          winnerUsername: selectedParticipant?.name || "Unknown",
        });
      });
    });
    return summary;
  }

  /**
   * Load the drawing data from the backend
   */
  async loadDrawingData() {
    this.loading = true;
    this.error = null;

    try {
      this.lotteryData = await ajax(
        `/vzekc-verlosung/lotteries/${this.args.model.topicId}/drawing-data`
      );

      // Auto-select packets with only one participant
      if (this.isManualMode) {
        this.autoSelectSingleParticipants();
      }
    } catch (error) {
      this.error = error.jqXHR?.responseJSON?.errors?.[0] || error.message;
    } finally {
      this.loading = false;
    }
  }

  /**
   * Auto-select winners for packets where participants <= quantity
   * When there are fewer or equal participants to quantity, auto-assign all
   */
  autoSelectSingleParticipants() {
    const selections = {};
    this.packetsWithParticipants.forEach((packet) => {
      const quantity = packet.quantity || 1;
      if (packet.participants.length <= quantity) {
        // Auto-select all participants (they all win)
        selections[packet.id] = packet.participants.map((p) => p.id.toString());
      } else if (quantity === 1 && packet.participants.length === 1) {
        // Single instance, single participant
        selections[packet.id] = [packet.participants[0].id.toString()];
      } else {
        // Multiple choices needed, initialize empty array
        selections[packet.id] = [];
      }
    });
    this.manualSelections = selections;
  }

  /**
   * Perform the drawing using lottery.js and submit results
   */
  @action
  async performDrawing() {
    if (this.drawing || this.drawn) {
      return;
    }

    this.drawing = true;
    this.error = null;

    try {
      // Create lottery instance with the data
      const lottery = new Lottery(this.lotteryData);

      // Initialize the RNG (this is async because it uses crypto API)
      await lottery.initialize();

      // Perform the drawing
      this.results = await lottery.draw();
      this.drawn = true;

      // Automatically submit the results
      await this.submitResults();
    } catch (error) {
      this.error = error.message;
      this.drawing = false;
    }
  }

  /**
   * Submit the results to the backend
   */
  @action
  async submitResults() {
    if (!this.results) {
      return;
    }

    try {
      await ajax(`/vzekc-verlosung/lotteries/${this.args.model.topicId}/draw`, {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify({
          results: this.results,
        }),
      });

      // Close modal and reload page to show winners
      this.args.closeModal();
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
      throw error;
    }
  }

  /**
   * Handle winner selection change for a packet instance (manual mode)
   *
   * @param {number} packetId
   * @param {number} instanceIndex - 0-based index for the instance
   * @param {Event} event
   */
  @action
  updateSelection(packetId, instanceIndex, event) {
    const userId = event.target.value;
    const currentSelections = [...(this.manualSelections[packetId] || [])];

    // Ensure array has enough slots
    while (currentSelections.length <= instanceIndex) {
      currentSelections.push("");
    }

    currentSelections[instanceIndex] = userId;

    this.manualSelections = {
      ...this.manualSelections,
      [packetId]: currentSelections,
    };
  }

  /**
   * Get available participants for a specific instance dropdown
   * Filters out participants already selected in other instances of same packet
   *
   * @param {Object} packet
   * @param {number} instanceIndex
   * @returns {Array}
   */
  getAvailableParticipants(packet, instanceIndex) {
    const selections = this.manualSelections[packet.id] || [];
    const selectedInOtherInstances = selections.filter(
      (s, idx) => idx !== instanceIndex && s && s !== ""
    );
    return packet.participants.filter(
      (p) => !selectedInOtherInstances.includes(p.id.toString())
    );
  }

  /**
   * Get number of instance dropdowns to show for a packet
   * Limited by available participants
   *
   * @param {Object} packet
   * @returns {Array}
   */
  getInstancesForPacket(packet) {
    const quantity = packet.quantity || 1;
    const count = Math.min(quantity, packet.participants.length);
    return Array.from({ length: count }, (_, i) => i);
  }

  /**
   * Check if a specific instance is auto-assigned (only one participant available)
   *
   * @param {Object} packet
   * @param {number} instanceIndex
   * @returns {boolean}
   */
  isInstanceAutoAssigned(packet, instanceIndex) {
    const available = this.getAvailableParticipants(packet, instanceIndex);
    return available.length === 1;
  }

  /**
   * Get the selected user ID for an instance
   *
   * @param {Object} packet
   * @param {number} instanceIndex
   * @returns {string}
   */
  getInstanceSelection(packet, instanceIndex) {
    const selections = this.manualSelections[packet.id] || [];
    return selections[instanceIndex] || "";
  }

  /**
   * Show confirmation dialog for manual selections
   */
  @action
  showConfirmationDialog() {
    if (!this.hasAllSelections) {
      this.error = i18n("vzekc_verlosung.drawing.missing_selections_error");
      return;
    }
    this.showConfirmation = true;
  }

  /**
   * Hide confirmation dialog
   */
  @action
  hideConfirmationDialog() {
    this.showConfirmation = false;
  }

  /**
   * Submit manual drawing results
   */
  @action
  async submitManualResults() {
    if (!this.hasAllSelections) {
      return;
    }

    this.drawing = true;
    this.error = null;

    try {
      await ajax(
        `/vzekc-verlosung/lotteries/${this.args.model.topicId}/draw-manual`,
        {
          type: "POST",
          contentType: "application/json",
          data: JSON.stringify({
            selections: this.manualSelections,
          }),
        }
      );

      // Close modal and reload page to show winners
      this.args.closeModal();
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
      this.drawing = false;
      this.showConfirmation = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "vzekc_verlosung.drawing.modal_title"}}
      @closeModal={{@closeModal}}
      class="draw-lottery-modal"
    >
      <:body>
        <div class="draw-lottery-content">
          {{#if this.loading}}
            <div class="draw-loading">
              {{icon "spinner" class="fa-spin"}}
              <p>{{i18n "vzekc_verlosung.drawing.loading"}}</p>
            </div>
          {{else if this.error}}
            <div class="draw-error">
              {{icon "triangle-exclamation"}}
              <p>{{this.error}}</p>
            </div>
          {{else if this.drawing}}
            <div class="draw-loading">
              {{icon "spinner" class="fa-spin"}}
              <p>{{i18n "vzekc_verlosung.drawing.loading"}}</p>
            </div>
          {{else if this.showConfirmation}}
            <div class="draw-confirmation">
              <div class="confirmation-message">
                {{icon "circle-check"}}
                <h4>{{i18n
                    "vzekc_verlosung.drawing.confirm_selections_title"
                  }}</h4>
                <p>{{i18n
                    "vzekc_verlosung.drawing.confirm_selections_message"
                  }}</p>
              </div>
              <div class="selections-summary">
                <ul>
                  {{#each this.selectionsSummary as |selection|}}
                    <li>
                      <strong>{{selection.packetTitle}}:</strong>
                      {{selection.winnerUsername}}
                    </li>
                  {{/each}}
                </ul>
              </div>
            </div>
          {{else if this.isManualMode}}
            <div class="draw-manual">
              <div class="manual-message">
                {{icon "hand-pointer"}}
                <p>{{i18n "vzekc_verlosung.drawing.manual_mode_message"}}</p>
              </div>
              {{#if this.packetsWithParticipants}}
                <div class="manual-selections">
                  {{#each this.packetsWithParticipants as |packet|}}
                    <div class="packet-selection">
                      <label>
                        {{packet.title}}
                        {{#if (gt packet.quantity 1)}}
                          <span
                            class="packet-quantity-badge"
                          >({{packet.quantity}}x)</span>
                        {{/if}}
                      </label>
                      <div class="instance-selections">
                        {{#each
                          (this.getInstancesForPacket packet)
                          as |instanceIdx|
                        }}
                          <div class="instance-selection">
                            {{#if (gt packet.quantity 1)}}
                              <span
                                class="instance-label"
                              >#{{instanceIdx}}</span>
                            {{/if}}
                            {{#if
                              (this.isInstanceAutoAssigned packet instanceIdx)
                            }}
                              <div class="single-participant">
                                <strong>{{get
                                    (this.getAvailableParticipants
                                      packet instanceIdx
                                    )
                                    "0.name"
                                  }}</strong>
                                <span class="only-ticket-note">(nur ein Ticket
                                  verfügbar)</span>
                              </div>
                            {{else}}
                              <select
                                {{on
                                  "change"
                                  (fn
                                    this.updateSelection packet.id instanceIdx
                                  )
                                }}
                              >
                                <option value="">-- Select Winner --</option>
                                {{#each
                                  (this.getAvailableParticipants
                                    packet instanceIdx
                                  )
                                  as |participant|
                                }}
                                  <option
                                    value={{participant.id}}
                                    selected={{eq
                                      participant.id
                                      (this.getInstanceSelection
                                        packet instanceIdx
                                      )
                                    }}
                                  >{{participant.name}}</option>
                                {{/each}}
                              </select>
                            {{/if}}
                          </div>
                        {{/each}}
                      </div>
                    </div>
                  {{/each}}
                </div>
              {{else}}
                <div class="no-participants">
                  <p>{{i18n
                      "vzekc_verlosung.drawing.no_participants_packet"
                    }}</p>
                </div>
              {{/if}}
            </div>
          {{else}}
            <div class="draw-ready">
              <div class="ready-message">
                {{icon "dice"}}
                <p>{{i18n "vzekc_verlosung.drawing.ready_message"}}</p>
              </div>
              {{#if this.lotteryData.packets}}
                <div class="packets-summary">
                  <h4>{{i18n "vzekc_verlosung.drawing.packets_to_draw"}}</h4>
                  <ul>
                    {{#each this.lotteryData.packets as |packet|}}
                      <li>
                        {{#if (gt packet.quantity 1)}}
                          <span
                            class="packet-quantity"
                          >{{packet.quantity}}x</span>
                        {{/if}}
                        {{packet.title}}
                        ({{packet.participants.length}}
                        {{i18n
                          "vzekc_verlosung.drawing.participants"
                          count=packet.participants.length
                        }})
                      </li>
                    {{/each}}
                  </ul>
                </div>
              {{/if}}
            </div>
          {{/if}}
        </div>
      </:body>

      <:footer>
        <div class="modal-footer-buttons">
          {{#if this.showConfirmation}}
            <DButton
              @action={{this.submitManualResults}}
              @translatedLabel={{i18n "vzekc_verlosung.drawing.confirm_button"}}
              @icon="check"
              @disabled={{this.drawing}}
              class="btn-primary"
            />
            <DButton
              @action={{this.hideConfirmationDialog}}
              @translatedLabel={{i18n "back"}}
              @disabled={{this.drawing}}
              class="btn-default"
            />
          {{else if
            (and (not this.loading) (not this.error) (not this.drawing))
          }}
            {{#if this.isManualMode}}
              <DButton
                @action={{this.showConfirmationDialog}}
                @translatedLabel={{i18n
                  "vzekc_verlosung.drawing.confirm_selections"
                }}
                @icon="hand-pointer"
                @disabled={{not this.hasAllSelections}}
                class="btn-primary"
              />
            {{else}}
              <DButton
                @action={{this.performDrawing}}
                @translatedLabel={{i18n "vzekc_verlosung.drawing.draw_button"}}
                @icon="dice"
                class="btn-primary"
              />
            {{/if}}
          {{/if}}
          <DButton
            @action={{@closeModal}}
            @translatedLabel={{i18n "cancel"}}
            @disabled={{this.drawing}}
            class="btn-default"
          />
        </div>
      </:footer>
    </DModal>
  </template>
}
