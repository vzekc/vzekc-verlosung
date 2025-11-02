import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { htmlSafe } from "@ember/template";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * Ticket count badge component with clickable participant list
 *
 * @component TicketCountBadge
 * Displays ticket count and shows participant list on click
 *
 * @param {number} args.count - Number of tickets
 * @param {Array} args.users - Array of user objects with id, username, name, avatar_template
 * @param {string} args.packetTitle - Optional title of the packet for the header
 */
export default class TicketCountBadge extends Component {
  @tracked showParticipants = false;
  @tracked modalTop = 0;
  @tracked modalLeft = 0;
  @tracked modalBottom = false;

  /**
   * Toggle participant list visibility and position it near the click
   */
  @action
  toggleParticipants(event) {
    event.preventDefault();
    event.stopPropagation();

    if (!this.showParticipants) {
      // Calculate position near the button
      const rect = event.currentTarget.getBoundingClientRect();
      const windowHeight = window.innerHeight;
      const estimatedModalHeight = 400; // Estimated max height of modal

      // Check if there's enough space below the button
      const spaceBelow = windowHeight - rect.bottom;
      const spaceAbove = rect.top;

      if (spaceBelow < estimatedModalHeight && spaceAbove > spaceBelow) {
        // Position above the button if not enough space below
        this.modalTop = rect.top - 10; // 10px above the button
        this.modalBottom = true;
      } else {
        // Position below the button (default)
        this.modalTop = rect.bottom + 10; // 10px below the button
        this.modalBottom = false;
      }

      // Ensure modal doesn't overflow off the right side of the screen
      const estimatedModalWidth = 400;
      const spaceRight = window.innerWidth - rect.left;
      if (spaceRight < estimatedModalWidth) {
        // Align to right edge if not enough space
        this.modalLeft = window.innerWidth - estimatedModalWidth - 20; // 20px margin
      } else {
        this.modalLeft = rect.left;
      }

      this.showParticipants = true;
    } else {
      this.showParticipants = false;
    }
  }

  /**
   * Close participant list when clicking the overlay
   */
  @action
  handleOverlayClick(event) {
    // Only close if clicking the overlay itself, not the content
    if (event.target.classList.contains("ticket-participants-modal")) {
      this.showParticipants = false;
    }
  }

  /**
   * Close on escape key
   */
  @action
  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.showParticipants = false;
    }
  }

  /**
   * Get the inline style for positioning the modal
   *
   * @type {string}
   */
  get modalStyle() {
    if (this.modalBottom) {
      // Position above the button - use bottom instead of top
      return htmlSafe(
        `position: fixed; bottom: ${window.innerHeight - this.modalTop}px; left: ${this.modalLeft}px;`
      );
    } else {
      // Position below the button (default)
      return htmlSafe(
        `position: fixed; top: ${this.modalTop}px; left: ${this.modalLeft}px;`
      );
    }
  }

  <template>
    <span class="ticket-count-badge-wrapper">
      <button
        type="button"
        class="ticket-count-badge"
        {{on "click" this.toggleParticipants}}
      >
        {{icon "tags"}}
        <span class="count">{{@count}}</span>
      </button>

      {{#if this.showParticipants}}
        {{! template-lint-disable no-invalid-interactive }}
        <div
          class="ticket-participants-modal"
          role="button"
          tabindex="0"
          {{on "click" this.handleOverlayClick}}
          {{on "keydown" this.handleKeyDown}}
        >
          <div class="ticket-participants-content" style={{this.modalStyle}}>
            {{#if @packetTitle}}
              <div class="ticket-participants-header">
                {{i18n "vzekc_verlosung.ticket.tickets_bought_for"}}
                {{@packetTitle}}
              </div>
            {{/if}}
            {{#if @users.length}}
              <div class="ticket-users-list">
                {{#each @users as |user|}}
                  <div class="ticket-user">
                    {{avatar user imageSize="tiny"}}
                    <span class="username">{{user.username}}</span>
                  </div>
                {{/each}}
              </div>
            {{else}}
              <div class="no-participants">{{i18n
                  "vzekc_verlosung.ticket.no_participants"
                }}</div>
            {{/if}}
          </div>
        </div>
      {{/if}}
    </span>
  </template>
}
