import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";

/**
 * Ticket count badge component with clickable participant list
 *
 * @component TicketCountBadge
 * Displays ticket count and shows participant list on click
 *
 * @param {number} args.count - Number of tickets
 * @param {Array} args.users - Array of user objects with id, username, name, avatar_template
 */
export default class TicketCountBadge extends Component {
  @tracked showParticipants = false;

  /**
   * Toggle participant list visibility
   */
  @action
  toggleParticipants(event) {
    event.preventDefault();
    event.stopPropagation();
    this.showParticipants = !this.showParticipants;
  }

  /**
   * Close participant list when clicking outside
   */
  @action
  handleClickOutside(event) {
    if (!event.target.closest(".ticket-count-badge-wrapper")) {
      this.showParticipants = false;
    }
  }

  <template>
    <span class="ticket-count-badge-wrapper">
      <button
        type="button"
        class="ticket-count-badge"
        {{on "click" this.toggleParticipants}}
      >
        {{icon "ticket"}}
        <span class="count">{{@count}}</span>
      </button>

      {{#if this.showParticipants}}
        {{! template-lint-disable no-invalid-interactive }}
        <div
          class="ticket-participants-modal"
          role="button"
          tabindex="0"
          {{on "click" this.handleClickOutside}}
          {{on "keydown" this.handleClickOutside}}
        >
          <div class="ticket-participants-content">
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
              <div class="no-participants">No participants yet</div>
            {{/if}}
          </div>
        </div>
      {{/if}}
    </span>
  </template>
}
