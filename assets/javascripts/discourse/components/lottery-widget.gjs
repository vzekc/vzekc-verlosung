import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import UserLink from "discourse/components/user-link";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import Composer from "discourse/models/composer";
import I18n, { i18n } from "discourse-i18n";
import TicketCountBadge from "./ticket-count-badge";

/**
 * Lottery widget component combining ticket button and count display
 *
 * @component LotteryWidget
 * Shows a button to buy/return lottery tickets and displays the ticket count with participants
 *
 * @param {Object} args.data.post - The post object (passed via renderGlimmer)
 */
export default class LotteryWidget extends Component {
  @service currentUser;
  @service appEvents;
  @service dialog;
  @service composer;
  @service siteSettings;

  @tracked hasTicket = false;
  @tracked ticketCount = 0;
  @tracked users = [];
  @tracked winnerData = null;
  @tracked collectedAt = null;
  @tracked erhaltungsberichtTopicId = null;
  @tracked loading = true;
  @tracked markingCollected = false;

  constructor() {
    super(...arguments);
    if (this.shouldShow) {
      this.loadTicketData();
      this.appEvents.on("lottery:ticket-changed", this, this.onTicketChanged);
      // Reload data when page becomes visible again
      document.addEventListener("visibilitychange", this.onVisibilityChange);
    } else {
      this.loading = false;
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    if (this.shouldShow) {
      this.appEvents.off("lottery:ticket-changed", this, this.onTicketChanged);
      document.removeEventListener("visibilitychange", this.onVisibilityChange);
    }
  }

  @bind
  onVisibilityChange() {
    // Reload data when page becomes visible (user returns from composer)
    if (!document.hidden && this.shouldShow) {
      this.loadTicketData();
    }
  }

  /**
   * Get the post object from component args
   *
   * @type {Object}
   */
  get post() {
    return this.args.data?.post;
  }

  @bind
  onTicketChanged(postId) {
    if (postId === this.post?.id) {
      this.loadTicketData();
    }
  }

  /**
   * Load ticket data for this lottery packet post including user's ticket status and count
   */
  async loadTicketData() {
    try {
      const result = await ajax(
        `/vzekc-verlosung/tickets/packet-status/${this.post.id}`
      );
      this.hasTicket = result.has_ticket;
      this.ticketCount = result.ticket_count;
      this.users = result.users || [];
      this.winnerData = result.winner || null;
      this.collectedAt = result.collected_at || null;

      // Always sync erhaltungsbericht_topic_id from post (will be null if not set or deleted)
      this.erhaltungsberichtTopicId =
        this.post?.erhaltungsbericht_topic_id || null;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * Toggle ticket status (buy or return)
   */
  @action
  async toggleTicket() {
    if (this.loading) {
      return;
    }

    this.loading = true;

    try {
      if (this.hasTicket) {
        // Return ticket
        await ajax(`/vzekc-verlosung/tickets/${this.post.id}`, {
          type: "DELETE",
        });
        this.hasTicket = false;
      } else {
        // Buy ticket
        await ajax("/vzekc-verlosung/tickets", {
          type: "POST",
          data: { post_id: this.post.id },
        });
        this.hasTicket = true;
      }

      // Emit event to update ticket count display
      this.appEvents.trigger("lottery:ticket-changed", this.post.id);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * Check if this widget should be shown
   * Only show on lottery packet posts for logged-in users
   *
   * @type {boolean}
   */
  get shouldShow() {
    return this.currentUser && this.post?.is_lottery_packet;
  }

  /**
   * Check if user can buy or return tickets
   * Returns false if lottery is not active or has ended
   *
   * @type {boolean}
   */
  get canBuyOrReturn() {
    const topic = this.post?.topic;

    // Check if lottery is active (not draft, not finished)
    if (topic?.lottery_state !== "active") {
      return false;
    }

    // Check if lottery has ended
    if (topic?.lottery_ends_at) {
      const endsAt = new Date(topic.lottery_ends_at);
      if (endsAt <= new Date()) {
        return false;
      }
    }
    return true;
  }

  /**
   * Check if lottery has ended
   *
   * @type {boolean}
   */
  get hasEnded() {
    const topic = this.post?.topic;
    if (topic?.lottery_ends_at) {
      const endsAt = new Date(topic.lottery_ends_at);
      return endsAt <= new Date();
    }
    return false;
  }

  /**
   * Check if lottery has been drawn
   *
   * @type {boolean}
   */
  get isDrawn() {
    const topic = this.post?.topic;
    return topic?.lottery_results != null;
  }

  /**
   * Get the winner for this packet
   * Prefers loaded winnerData from API, falls back to post custom field
   *
   * @type {Object|string|null}
   */
  get winner() {
    // Prefer the winner data loaded from API (includes avatar)
    if (this.winnerData) {
      return this.winnerData;
    }
    // Fall back to post custom field (just username string)
    return this.post?.lottery_winner;
  }

  /**
   * Get winner username (handles both string and object)
   *
   * @type {string|null}
   */
  get winnerUsername() {
    const winner = this.winner;
    if (!winner) {
      return null;
    }
    return typeof winner === "string" ? winner : winner.username;
  }

  /**
   * Check if winner is a full user object with avatar_template
   *
   * @type {boolean}
   */
  get hasWinnerObject() {
    const winner = this.winner;
    return winner && typeof winner === "object" && winner.avatar_template;
  }

  /**
   * Get the button label based on ticket status
   *
   * @type {string}
   */
  get buttonLabel() {
    if (this.loading) {
      return "vzekc_verlosung.ticket.loading";
    }
    return this.hasTicket
      ? "vzekc_verlosung.ticket.return"
      : "vzekc_verlosung.ticket.buy";
  }

  /**
   * Get the button icon based on ticket status
   *
   * @type {string}
   */
  get buttonIcon() {
    return this.hasTicket ? "xmark" : "gift";
  }

  /**
   * Extract packet title from post content (first heading)
   *
   * @type {string}
   */
  get packetTitle() {
    if (!this.post?.cooked) {
      return "";
    }
    const tempDiv = document.createElement("div");
    tempDiv.innerHTML = this.post.cooked;
    const heading = tempDiv.querySelector("h1, h2, h3");
    return heading ? heading.textContent.trim() : "";
  }

  /**
   * Check if current user is the lottery owner
   *
   * @type {boolean}
   */
  get isLotteryOwner() {
    const topic = this.post?.topic;
    return (
      this.currentUser &&
      topic &&
      (this.currentUser.admin ||
        this.currentUser.staff ||
        topic.user_id === this.currentUser.id)
    );
  }

  /**
   * Check if the "Mark as Collected" button should be shown
   *
   * @type {boolean}
   */
  get canMarkAsCollected() {
    return (
      this.isLotteryOwner && this.winner && !this.collectedAt && !this.loading
    );
  }

  /**
   * Format collected date for display
   *
   * @type {string|null}
   */
  get formattedCollectedDate() {
    if (!this.collectedAt) {
      return null;
    }
    const date = new Date(this.collectedAt);
    // Use user's locale from Discourse
    const locale = I18n.locale || "en";
    return date.toLocaleDateString(locale, {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  }

  /**
   * Mark packet as collected (with confirmation)
   */
  @action
  async markAsCollected() {
    if (this.markingCollected) {
      return;
    }

    const confirmed = await this.dialog.confirm({
      message: i18n("vzekc_verlosung.collection.confirm_message", {
        winner: this.winnerUsername,
        packet: this.packetTitle,
      }),
      didConfirm: () => true,
      didCancel: () => false,
    });

    if (!confirmed) {
      return;
    }

    this.markingCollected = true;

    try {
      const result = await ajax(
        `/vzekc-verlosung/packets/${this.post.id}/mark-collected`,
        {
          type: "POST",
        }
      );

      // Update local state with response
      this.collectedAt = result.collected_at || null;

      // Show success message
      this.dialog.alert(i18n("vzekc_verlosung.collection.success_message"));
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.markingCollected = false;
    }
  }

  /**
   * Check if current user is the winner of this packet
   *
   * @type {boolean}
   */
  get isWinner() {
    return (
      this.currentUser &&
      this.winnerUsername &&
      this.currentUser.username === this.winnerUsername
    );
  }

  /**
   * Check if Erhaltungsbericht button should be shown
   *
   * @type {boolean}
   */
  get canCreateErhaltungsbericht() {
    return (
      this.isWinner &&
      this.collectedAt &&
      !this.erhaltungsberichtTopicId &&
      !this.loading
    );
  }

  /**
   * Get URL to Erhaltungsbericht topic if it exists
   *
   * @type {string|null}
   */
  get erhaltungsberichtUrl() {
    if (!this.erhaltungsberichtTopicId) {
      return null;
    }
    return `/t/${this.erhaltungsberichtTopicId}`;
  }

  /**
   * Create Erhaltungsbericht topic for this packet
   * Opens the composer with pre-filled content instead of creating immediately
   */
  @action
  createErhaltungsbericht() {
    // Get category and template
    const categoryId =
      this.siteSettings.vzekc_verlosung_erhaltungsberichte_category_id;

    if (!categoryId) {
      this.dialog.alert(
        i18n("vzekc_verlosung.erhaltungsbericht.category_not_configured")
      );
      return;
    }

    // Get template and replace placeholders
    const packetTitle = this.packetTitle || `Paket #${this.post.post_number}`;
    const lotteryTitle = this.post.topic.title;
    const packetUrl = `${window.location.origin}/t/${this.post.topic.slug}/${this.post.topic_id}/${this.post.post_number}`;

    // Compose topic title: "<packet-title> aus <lottery-title>"
    const topicTitle = `${packetTitle} aus ${lotteryTitle}`;

    // Get template from site settings or use default German template
    let templateText =
      this.siteSettings.vzekc_verlosung_erhaltungsbericht_template ||
      `Ich habe folgendes Paket aus der Verlosung "[LOTTERY_TITLE]" erhalten:\n\n## Was war im Paket?\n\n[Beschreibe hier, was du erhalten hast]\n\n## Zustand und erste Eindrücke\n\n[Wie ist der Zustand? Was waren deine ersten Eindrücke?]\n\n## Fotos\n\n[Füge hier Fotos hinzu]\n\n## Pläne für die Hardware\n\n[Was hast du mit der Hardware vor? Sammlung, Restaurierung, Nutzung?]\n\n---\n\nLink zum Paket: [PACKET_LINK]`;

    const template = templateText
      .replace("[LOTTERY_TITLE]", lotteryTitle)
      .replace("[PACKET_LINK]", packetUrl);

    // Open composer with pre-filled content and packet reference
    // Use unique draftKey with timestamp to prevent draft conflicts
    this.composer.open({
      action: Composer.CREATE_TOPIC,
      categoryId,
      title: topicTitle,
      reply: template,
      draftKey: `new_topic_erhaltungsbericht_${this.post.id}_${Date.now()}`,
      // These custom fields will be serialized to the topic
      // Keys must match first parameter of serializeToDraft in erhaltungsbericht-composer.js
      packet_post_id: this.post.id,
      packet_topic_id: this.post.topic_id,
    });
  }

  <template>
    {{#if this.shouldShow}}
      <div class="lottery-packet-status">
        {{#if this.isDrawn}}
          {{! Lottery has been drawn - show winner or no winner message }}
          {{#if this.winner}}
            <div class="lottery-packet-winner-notice">
              {{#unless this.loading}}
                <div class="participants-display">
                  <span class="participants-label">{{i18n
                      "vzekc_verlosung.ticket.participants"
                    }}</span>
                  <TicketCountBadge
                    @count={{this.ticketCount}}
                    @users={{this.users}}
                    @packetTitle={{this.packetTitle}}
                  />
                </div>
              {{/unless}}
              <div class="winner-message">
                <span class="participants-label">{{i18n
                    "vzekc_verlosung.ticket.winner"
                  }}</span>
                {{#if this.hasWinnerObject}}
                  <UserLink
                    @username={{this.winnerUsername}}
                    class="winner-user-link"
                  >
                    {{avatar this.winner imageSize="small"}}
                    <span class="winner-name">{{this.winnerUsername}}</span>
                  </UserLink>
                {{else}}
                  <UserLink
                    @username={{this.winnerUsername}}
                    class="winner-user-link"
                  >
                    <span class="winner-name">{{this.winnerUsername}}</span>
                  </UserLink>
                {{/if}}
              </div>
              {{! Collection tracking - only visible to lottery owner }}
              {{#if this.isLotteryOwner}}
                <div class="collection-tracking">
                  {{#if this.collectedAt}}
                    <div class="collection-status collected">
                      <span class="collection-icon">✓</span>
                      <span class="collection-text">{{i18n
                          "vzekc_verlosung.collection.collected_on"
                          date=this.formattedCollectedDate
                        }}</span>
                    </div>
                  {{else if this.canMarkAsCollected}}
                    <DButton
                      @action={{this.markAsCollected}}
                      @label="vzekc_verlosung.collection.mark_collected"
                      @icon="check"
                      @disabled={{this.markingCollected}}
                      class="btn-default mark-collected-button"
                    />
                  {{/if}}
                </div>
              {{/if}}
              {{! Erhaltungsbericht button - only visible to winner }}
              {{#if this.canCreateErhaltungsbericht}}
                <div class="erhaltungsbericht-section">
                  <DButton
                    @action={{this.createErhaltungsbericht}}
                    @label="vzekc_verlosung.erhaltungsbericht.create_button"
                    @icon="pen"
                    class="btn-primary create-erhaltungsbericht-button"
                  />
                </div>
              {{/if}}
              {{! Link to Erhaltungsbericht - visible to everyone }}
              {{#if this.erhaltungsberichtUrl}}
                <div class="erhaltungsbericht-link-section">
                  <a
                    href={{this.erhaltungsberichtUrl}}
                    class="erhaltungsbericht-link"
                  >
                    {{icon "file"}}
                    <span>{{i18n
                        "vzekc_verlosung.erhaltungsbericht.view_link"
                      }}</span>
                  </a>
                </div>
              {{/if}}
            </div>
          {{else}}
            <div class="lottery-packet-no-winner-notice">
              <div class="no-winner-message">{{i18n
                  "vzekc_verlosung.ticket.no_winner"
                }}</div>
            </div>
          {{/if}}
        {{else if this.canBuyOrReturn}}
          {{! Lottery is active - show buy/return button }}
          <div class="lottery-packet-active-notice">
            <div class="action-section">
              <DButton
                @action={{this.toggleTicket}}
                @label={{this.buttonLabel}}
                @icon={{this.buttonIcon}}
                @disabled={{this.loading}}
                class="btn-primary lottery-ticket-button"
              />
            </div>
            {{#unless this.loading}}
              <div class="participants-display">
                <span class="participants-label">{{i18n
                    "vzekc_verlosung.ticket.participants"
                  }}</span>
                <TicketCountBadge
                  @count={{this.ticketCount}}
                  @users={{this.users}}
                  @packetTitle={{this.packetTitle}}
                />
              </div>
            {{/unless}}
          </div>
        {{else if this.hasEnded}}
          {{! Lottery has ended but not drawn yet - show participants only }}
          <div class="lottery-packet-ended-notice">
            {{#unless this.loading}}
              <div class="participants-display">
                <span class="participants-label">{{i18n
                    "vzekc_verlosung.ticket.participants"
                  }}</span>
                <TicketCountBadge
                  @count={{this.ticketCount}}
                  @users={{this.users}}
                  @packetTitle={{this.packetTitle}}
                  @hasEnded={{true}}
                />
              </div>
            {{/unless}}
          </div>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
