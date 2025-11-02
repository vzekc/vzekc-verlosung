import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { htmlSafe } from "@ember/template";
import UserLink from "discourse/components/user-link";
import avatar from "discourse/helpers/avatar";
import { i18n } from "discourse-i18n";

/**
 * Ticket count badge component with inline avatar display
 *
 * @component TicketCountBadge
 * Displays ticket participants as inline avatars with overflow indicator
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
  @tracked modalMaxHeight = 400;

  maxAvatarsToShow = 5;

  /**
   * Get the list of users to display as avatars
   *
   * @type {Array}
   */
  get displayedUsers() {
    const users = this.args.users || [];
    return users.slice(0, this.maxAvatarsToShow);
  }

  /**
   * Get the count of remaining users not shown
   *
   * @type {number|null}
   */
  get remainingCount() {
    const users = this.args.users || [];
    const remaining = users.length - this.maxAvatarsToShow;
    return remaining > 0 ? remaining : null;
  }

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
      const margin = 20; // Margin from screen edges

      // Check if there's enough space below the button
      const spaceBelow = windowHeight - rect.bottom - margin;
      const spaceAbove = rect.top - margin;

      if (spaceBelow < 200 && spaceAbove > spaceBelow) {
        // Position above the button if not enough space below
        this.modalTop = rect.top - 10; // 10px above the button
        this.modalBottom = true;
        this.modalMaxHeight = Math.max(200, spaceAbove - 10);
      } else {
        // Position below the button (default)
        this.modalTop = rect.bottom + 10; // 10px below the button
        this.modalBottom = false;
        this.modalMaxHeight = Math.max(200, spaceBelow - 10);
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
        `position: fixed; bottom: ${window.innerHeight - this.modalTop}px; left: ${this.modalLeft}px; max-height: ${this.modalMaxHeight}px;`
      );
    } else {
      // Position below the button (default)
      return htmlSafe(
        `position: fixed; top: ${this.modalTop}px; left: ${this.modalLeft}px; max-height: ${this.modalMaxHeight}px;`
      );
    }
  }

  <template>
    <div class="ticket-participants-inline">
      {{#if @users.length}}
        {{#each this.displayedUsers as |user|}}
          <UserLink
            @username={{user.username}}
            class="ticket-participant-avatar"
          >
            {{avatar user imageSize="small"}}
          </UserLink>
        {{/each}}

        {{#if this.remainingCount}}
          <button
            type="button"
            class="ticket-participants-more"
            {{on "click" this.toggleParticipants}}
          >
            +{{this.remainingCount}}
          </button>
        {{/if}}
      {{else}}
        <span class="no-tickets">{{i18n
            "vzekc_verlosung.ticket.no_participants"
          }}</span>
      {{/if}}

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
            <div class="ticket-users-list">
              {{#each @users as |user|}}
                <div class="ticket-user">
                  {{avatar user imageSize="tiny"}}
                  <span class="username">{{user.username}}</span>
                </div>
              {{/each}}
            </div>
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
