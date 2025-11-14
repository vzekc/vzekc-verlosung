import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { schedule } from "@ember/runloop";
import { service } from "@ember/service";
import { eq, gt, not } from "truth-helpers";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import autoFocus from "discourse/modifiers/auto-focus";
import { i18n, i18n as i18nFn } from "discourse-i18n";

/**
 * Modal component for creating a new lottery with multiple packets
 *
 * @component CreateLotteryModal
 * Single-step modal to create lottery with title and packets
 */
export default class CreateLotteryModal extends Component {
  @service router;

  @tracked title = "";
  @tracked durationDays = 14;
  @tracked noAbholerpaket = false;
  @tracked abholerpaketTitle = "";
  @tracked packets = [this.createEmptyPacket()];
  @tracked isSubmitting = false;
  @tracked lastAddedPacketIndex = 0;

  /**
   * Check if user can submit
   *
   * @type {boolean}
   */
  get canSubmit() {
    return (
      this.title.trim().length >= 3 &&
      this.durationDays >= 7 &&
      this.durationDays <= 28 &&
      this.packets.length > 0 &&
      this.packets.every((p) => p.title.trim().length > 0)
    );
  }

  /**
   * Creates an empty packet object
   *
   * @returns {Object} Empty packet with default values
   */
  createEmptyPacket() {
    return {
      title: "",
      description: "",
      erhaltungsberichtRequired: true,
    };
  }

  /**
   * Adds a new packet to the list
   */
  @action
  addPacket() {
    this.packets = [...this.packets, this.createEmptyPacket()];
    this.lastAddedPacketIndex = this.packets.length - 1;

    // Focus the newly added packet input after render
    schedule("afterRender", () => {
      const inputs = document.querySelectorAll(
        ".create-lottery-modal .packet-item input[type='text']"
      );
      const lastInput = inputs[this.lastAddedPacketIndex];
      if (lastInput) {
        lastInput.focus();
      }
    });
  }

  /**
   * Removes a packet from the list
   *
   * @param {number} index - Index of packet to remove
   */
  @action
  removePacket(index) {
    if (this.packets.length > 1) {
      this.packets = this.packets.filter((_, i) => i !== index);
    }
  }

  /**
   * Updates a packet field
   *
   * @param {number} index - Packet index
   * @param {string} field - Field name to update
   * @param {Event} event - Input event
   */
  @action
  updatePacket(index, field, event) {
    const value =
      event.target.type === "checkbox"
        ? event.target.checked
        : event.target.value;
    // Update the field directly for smooth typing
    this.packets[index][field] = value;
    // Trigger reactivity by reassigning the array
    this.packets = [...this.packets];
  }

  /**
   * Updates main lottery field
   *
   * @param {string} field - Field name
   * @param {Event} event - Input event
   */
  @action
  updateField(field, event) {
    const value = event.target.value;
    // Convert to number for durationDays field
    if (field === "durationDays") {
      this[field] = parseInt(value, 10);
    } else {
      this[field] = value;
    }
  }

  /**
   * Toggle Abholerpaket exclusion
   *
   * @param {Event} event - Change event
   */
  @action
  toggleNoAbholerpaket(event) {
    this.noAbholerpaket = event.target.checked;
  }

  /**
   * Get packet number for display (1-indexed)
   *
   * @param {number} index - Zero-based index
   * @returns {number} One-based packet number
   */
  getPacketNumber(index) {
    return index + 1;
  }

  /**
   * Get the submit button label
   *
   * @type {string}
   */
  get submitLabel() {
    return this.isSubmitting
      ? i18nFn("vzekc_verlosung.modal.creating")
      : i18nFn("vzekc_verlosung.modal.create");
  }

  /**
   * Get the submit button icon
   *
   * @type {string}
   */
  get submitIcon() {
    return this.isSubmitting ? "spinner" : null;
  }

  /**
   * Prevent Enter key from submitting forms
   *
   * @param {KeyboardEvent} event - Keyboard event
   */
  @action
  handleKeyDown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      event.stopPropagation();
      return false;
    }
  }

  /**
   * Prevent form submission
   *
   * @param {Event} event - Submit event
   */
  @action
  preventSubmit(event) {
    event.preventDefault();
    return false;
  }

  /**
   * Submit the lottery creation
   */
  @action
  async submit() {
    if (this.isSubmitting || !this.canSubmit) {
      return;
    }

    this.isSubmitting = true;

    try {
      const result = await ajax("/vzekc-verlosung/lotteries", {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify({
          title: this.title,
          duration_days: this.durationDays,
          category_id: this.args.model.categoryId,
          has_abholerpaket: !this.noAbholerpaket,
          abholerpaket_title: this.abholerpaketTitle,
          packets: this.packets.map((p) => ({
            title: p.title,
            erhaltungsbericht_required: p.erhaltungsberichtRequired,
          })),
        }),
      });

      this.args.closeModal();

      // Navigate to the created main topic
      if (result.main_topic) {
        this.router.transitionTo(
          "topic",
          result.main_topic.slug,
          result.main_topic.id
        );
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSubmitting = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "vzekc_verlosung.modal.title"}}
      @closeModal={{@closeModal}}
      class="create-lottery-modal"
    >
      <:body>
        <form {{on "submit" this.preventSubmit}} class="lottery-form">
          <div class="control-group">
            <label>{{i18n "vzekc_verlosung.modal.title_label"}}</label>
            <input
              type="text"
              {{on "input" (fn this.updateField "title")}}
              {{on "keydown" this.handleKeyDown}}
              {{autoFocus}}
              value={{this.title}}
              placeholder={{i18n "vzekc_verlosung.modal.title_placeholder"}}
              class="lottery-title-input"
            />
          </div>

          <div class="control-group">
            <label>{{i18n "vzekc_verlosung.modal.duration_label"}}</label>
            <input
              type="number"
              {{on "input" (fn this.updateField "durationDays")}}
              {{on "keydown" this.handleKeyDown}}
              value={{this.durationDays}}
              min="7"
              max="28"
              class="lottery-duration-input"
            />
            <div class="duration-help">
              {{i18n "vzekc_verlosung.modal.duration_help"}}
            </div>
          </div>

          <div class="control-group abholerpaket-section">
            <label>{{i18n
                "vzekc_verlosung.modal.abholerpaket_title_label"
              }}</label>
            <div class="packet-input-with-prefix">
              <span class="packet-number-prefix">Paket 0:</span>
              <input
                type="text"
                {{on "input" (fn this.updateField "abholerpaketTitle")}}
                {{on "keydown" this.handleKeyDown}}
                value={{this.abholerpaketTitle}}
                placeholder={{i18n
                  "vzekc_verlosung.modal.abholerpaket_title_placeholder"
                }}
                class="abholerpaket-title-input"
                disabled={{this.noAbholerpaket}}
              />
            </div>
            <label class="checkbox-label">
              <input
                type="checkbox"
                {{on "change" this.toggleNoAbholerpaket}}
                checked={{this.noAbholerpaket}}
              />
              {{i18n "vzekc_verlosung.modal.no_abholerpaket_label"}}
            </label>
            <div class="abholerpaket-help">
              {{i18n "vzekc_verlosung.modal.no_abholerpaket_help"}}
            </div>
          </div>

          <div class="control-group">
            <label>{{i18n "vzekc_verlosung.modal.packets_label"}}</label>
            <div class="packets-list">
              {{#each this.packets as |packet index|}}
                <div class="packet-item">
                  <div class="packet-input-group">
                    <div class="packet-input-with-prefix">
                      <span class="packet-number-prefix">Paket
                        {{this.getPacketNumber index}}:</span>
                      <input
                        type="text"
                        {{on "input" (fn this.updatePacket index "title")}}
                        {{on "keydown" this.handleKeyDown}}
                        {{(if (eq index this.lastAddedPacketIndex) autoFocus)}}
                        value={{packet.title}}
                        placeholder={{i18n
                          "vzekc_verlosung.modal.packet_title_placeholder"
                          number=(this.getPacketNumber index)
                        }}
                      />
                    </div>
                    {{#if (gt this.packets.length 1)}}
                      <DButton
                        @action={{fn this.removePacket index}}
                        @icon="trash-can"
                        @title="vzekc_verlosung.modal.remove_packet"
                        class="btn-danger btn-small"
                      />
                    {{/if}}
                  </div>
                  <div class="packet-checkbox-group">
                    <label class="checkbox-label">
                      <input
                        type="checkbox"
                        {{on
                          "change"
                          (fn
                            this.updatePacket index "erhaltungsberichtRequired"
                          )
                        }}
                        checked={{packet.erhaltungsberichtRequired}}
                      />
                      {{i18n
                        "vzekc_verlosung.modal.erhaltungsbericht_required_label"
                      }}
                    </label>
                  </div>
                </div>
              {{/each}}
            </div>

            <DButton
              @action={{this.addPacket}}
              @icon="plus"
              @label="vzekc_verlosung.modal.add_packet"
              class="btn-default"
            />
          </div>
        </form>
      </:body>

      <:footer>
        <DButton
          @action={{this.submit}}
          @translatedLabel={{this.submitLabel}}
          @icon={{this.submitIcon}}
          @disabled={{not this.canSubmit}}
          class="btn-primary"
        />
      </:footer>
    </DModal>
  </template>
}
