import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { eq, gt, lt, not } from "truth-helpers";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n, i18n as i18nFn } from "discourse-i18n";

/**
 * Modal component for creating a new lottery with multiple packets
 *
 * @component CreateLotteryModal
 * Guides users through a multi-step process to create lottery topics
 *
 * Steps:
 * 1. Main lottery details (title, description)
 * 2. Add packets with title, description, and optional image
 * 3. Review and confirm
 */
export default class CreateLotteryModal extends Component {
  @service router;

  @tracked step = 1;
  @tracked title = "";
  @tracked description = "";
  @tracked packets = [this.createEmptyPacket()];
  @tracked isSubmitting = false;

  /**
   * Total number of steps in the wizard
   *
   * @type {number}
   */
  get totalSteps() {
    return 3;
  }

  /**
   * Check if user can proceed to next step
   *
   * @type {boolean}
   */
  get canProceed() {
    if (this.step === 1) {
      return (
        this.title.trim().length >= 3 && this.description.trim().length > 0
      );
    }
    if (this.step === 2) {
      return (
        this.packets.length > 0 &&
        this.packets.every((p) => p.title.trim().length > 0)
      );
    }
    return true;
  }

  /**
   * Get title for current step
   *
   * @type {string}
   */
  get stepTitle() {
    switch (this.step) {
      case 1:
        return i18nFn("vzekc_verlosung.modal.step1_title");
      case 2:
        return i18nFn("vzekc_verlosung.modal.step2_title");
      case 3:
        return i18nFn("vzekc_verlosung.modal.step3_title");
      default:
        return "";
    }
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
    };
  }

  /**
   * Adds a new packet to the list
   */
  @action
  addPacket() {
    this.packets = [...this.packets, this.createEmptyPacket()];
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
    const value = event.target.value;
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
    this[field] = event.target.value;
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
   * Go to next step
   */
  @action
  nextStep() {
    if (this.canProceed && this.step < this.totalSteps) {
      this.step++;
    }
  }

  /**
   * Go to previous step
   */
  @action
  previousStep() {
    if (this.step > 1) {
      this.step--;
    }
  }

  /**
   * Submit the lottery creation
   */
  @action
  async submit() {
    if (this.isSubmitting) {
      return;
    }

    this.isSubmitting = true;

    try {
      const result = await ajax("/vzekc-verlosung/lotteries", {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify({
          title: this.title,
          description: this.description,
          category_id: this.args.model.categoryId,
          packets: this.packets.map((p) => ({
            title: p.title,
            description: p.description,
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
      @title={{this.stepTitle}}
      @closeModal={{@closeModal}}
      class="create-lottery-modal"
    >
      <:body>
        <div class="lottery-wizard">
          <div class="wizard-progress">
            <span>{{this.step}} / {{this.totalSteps}}</span>
          </div>

          {{#if (eq this.step 1)}}
            <div class="wizard-step step-main-details">
              <div class="control-group">
                <label>{{i18n "vzekc_verlosung.modal.title_label"}}</label>
                <input
                  type="text"
                  {{on "input" (fn this.updateField "title")}}
                  value={{this.title}}
                  placeholder={{i18n "vzekc_verlosung.modal.title_placeholder"}}
                  class="lottery-title-input"
                />
              </div>

              <div class="control-group">
                <label>{{i18n
                    "vzekc_verlosung.modal.description_label"
                  }}</label>
                <textarea
                  {{on "input" (fn this.updateField "description")}}
                  value={{this.description}}
                  placeholder={{i18n
                    "vzekc_verlosung.modal.description_placeholder"
                  }}
                  rows="6"
                  class="lottery-description-input"
                ></textarea>
              </div>
            </div>
          {{/if}}

          {{#if (eq this.step 2)}}
            <div class="wizard-step step-packets">
              <div class="packets-list">
                {{#each this.packets as |packet index|}}
                  <div class="packet-item">
                    <div class="packet-header">
                      <h4>{{i18n "vzekc_verlosung.modal.packet_label"}}
                        {{this.getPacketNumber index}}</h4>
                      {{#if (gt this.packets.length 1)}}
                        <DButton
                          @action={{fn this.removePacket index}}
                          @icon="trash-can"
                          @title="vzekc_verlosung.modal.remove_packet"
                          class="btn-danger btn-small"
                        />
                      {{/if}}
                    </div>
                    <input
                      type="text"
                      {{on "input" (fn this.updatePacket index "title")}}
                      value={{packet.title}}
                      placeholder={{i18n
                        "vzekc_verlosung.modal.packet_title_placeholder"
                      }}
                    />
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
          {{/if}}

          {{#if (eq this.step 3)}}
            <div class="wizard-step step-review">
              <h3>{{this.title}}</h3>
              <p class="lottery-description">{{this.description}}</p>

              <h4>{{i18n
                  "vzekc_verlosung.modal.packets_count"
                  count=this.packets.length
                }}</h4>
              <ul class="packet-list">
                {{#each this.packets as |packet index|}}
                  <li>
                    <strong>{{this.getPacketNumber index}}.
                      {{packet.title}}</strong>
                    {{#if packet.description}}
                      <p>{{packet.description}}</p>
                    {{/if}}
                  </li>
                {{/each}}
              </ul>
            </div>
          {{/if}}
        </div>
      </:body>

      <:footer>
        <div class="modal-footer-buttons">
          {{#if (gt this.step 1)}}
            <DButton
              @action={{this.previousStep}}
              @label="vzekc_verlosung.modal.back"
              class="btn-default"
            />
          {{/if}}

          {{#if (lt this.step this.totalSteps)}}
            <DButton
              @action={{this.nextStep}}
              @label="vzekc_verlosung.modal.next"
              @disabled={{not this.canProceed}}
              class="btn-primary"
            />
          {{else}}
            <DButton
              @action={{this.submit}}
              @translatedLabel={{this.submitLabel}}
              @icon={{this.submitIcon}}
              @disabled={{this.isSubmitting}}
              class="btn-primary"
            />
          {{/if}}
        </div>
      </:footer>
    </DModal>
  </template>
}
