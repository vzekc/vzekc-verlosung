import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { and, not } from "truth-helpers";
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

  constructor() {
    super(...arguments);
    this.loadDrawingData();
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
    } catch (error) {
      this.error = error.jqXHR?.responseJSON?.errors?.[0] || error.message;
    } finally {
      this.loading = false;
    }
  }

  /**
   * Perform the drawing using lottery.js
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
    } catch (error) {
      this.error = error.message;
    } finally {
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

    this.drawing = true;
    this.error = null;

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
      this.error = error.jqXHR?.responseJSON?.errors?.[0] || error.message;
    } finally {
      this.drawing = false;
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
              {{icon "exclamation-triangle"}}
              <p>{{this.error}}</p>
            </div>
          {{else if this.drawn}}
            <div class="draw-results">
              <div class="results-header">
                {{icon "trophy"}}
                <h3>{{i18n "vzekc_verlosung.drawing.winners"}}</h3>
              </div>
              <ul class="winners-list">
                {{#each this.results.drawings as |drawing|}}
                  <li class="winner-item">
                    <strong>{{drawing.text}}</strong>
                    <span class="winner-name">{{drawing.winner}}</span>
                  </li>
                {{/each}}
              </ul>
              <p class="draw-info">
                {{i18n "vzekc_verlosung.drawing.verification_info"}}
              </p>
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
          {{#if this.drawn}}
            <DButton
              @action={{this.submitResults}}
              @translatedLabel={{i18n "vzekc_verlosung.drawing.confirm_button"}}
              @icon="check"
              @disabled={{this.drawing}}
              class="btn-primary"
            />
          {{else if (and (not this.loading) (not this.error))}}
            <DButton
              @action={{this.performDrawing}}
              @translatedLabel={{i18n "vzekc_verlosung.drawing.draw_button"}}
              @icon="dice"
              @disabled={{this.drawing}}
              class="btn-primary"
            />
          {{/if}}
          <DButton
            @action={{@closeModal}}
            @translatedLabel={{i18n "cancel"}}
            class="btn-default"
          />
        </div>
      </:footer>
    </DModal>
  </template>
}
