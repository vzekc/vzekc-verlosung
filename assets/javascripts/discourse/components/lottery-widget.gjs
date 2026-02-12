import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
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
import { and, eq, or } from "discourse/truth-helpers";
import I18n, { i18n } from "discourse-i18n";
import MarkShippedModal from "./modal/mark-shipped-modal";
import TicketCountBadge from "./ticket-count-badge";

/**
 * Lottery widget component combining ticket button and count display
 *
 * @component LotteryWidget
 * Shows a button to draw/return lottery tickets and displays the ticket count with participants
 *
 * @param {Object} args.data.post - The post object (passed via renderGlimmer)
 */
export default class LotteryWidget extends Component {
  @service currentUser;
  @service appEvents;
  @service dialog;
  @service modal;
  @service composer;
  @service siteSettings;

  @tracked hasTicket = false;
  @tracked ticketCount = 0;
  @tracked users = [];
  @tracked winnersData = []; // Array of winner entries with instance_number, user, collected_at, etc.
  @tracked loading = true;
  @tracked markingCollected = null; // Track which instance is being marked as collected
  @tracked markingShipped = null; // Track which instance is being marked as shipped
  @tracked notificationsSilenced = false;

  constructor() {
    super(...arguments);
    // Bind methods that are used in template subexpressions
    this.canMarkEntryAsCollected = this.canMarkEntryAsCollected.bind(this);
    this.canWinnerMarkAsCollected = this.canWinnerMarkAsCollected.bind(this);
    this.canMarkEntryAsShipped = this.canMarkEntryAsShipped.bind(this);
    this.canCreateErhaltungsberichtForEntry =
      this.canCreateErhaltungsberichtForEntry.bind(this);

    if (this.shouldShow) {
      // Load from serialized/cached post data (updated when tickets change)
      this.loadTicketDataFromPost();
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
      this.loadTicketDataFromAjax();
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
  onTicketChanged(eventData) {
    // Only update if triggered by another component for this post
    // The current component already updates its state directly from the API response
    if (eventData.postId === this.post?.id && !this._isToggling) {
      // Update local state from event data (no AJAX needed)
      this.hasTicket = eventData.hasTicket;
      this.ticketCount = eventData.ticketCount;
      this.users = eventData.users || [];

      // Update cached post data
      if (this.post) {
        this.post.packet_ticket_status = {
          ...this.post.packet_ticket_status,
          has_ticket: eventData.hasTicket,
          ticket_count: eventData.ticketCount,
          users: eventData.users || [],
        };
      }
    }
  }

  /**
   * Load ticket data from serialized post data (no AJAX request)
   */
  loadTicketDataFromPost() {
    try {
      // Ticket status is already serialized in the post data
      const status = this.post?.packet_ticket_status;
      if (status) {
        this.hasTicket = status.has_ticket || false;
        this.ticketCount = status.ticket_count || 0;
        this.users = status.users || [];
        // Support both old format (winner) and new format (winners array)
        this.winnersData =
          status.winners ||
          (status.winner ? [{ instance_number: 1, ...status.winner }] : []);
        this.notificationsSilenced = status.notifications_silenced || false;
      }
    } finally {
      this.loading = false;
    }
  }

  /**
   * Reload ticket data via AJAX (only when tickets change)
   */
  async loadTicketDataFromAjax() {
    try {
      const result = await ajax(
        `/vzekc-verlosung/tickets/packet-status/${this.post.id}`
      );
      this.hasTicket = result.has_ticket;
      this.ticketCount = result.ticket_count;
      this.users = result.users || [];
      // Support both old format (winner) and new format (winners array)
      this.winnersData =
        result.winners ||
        (result.winner ? [{ instance_number: 1, ...result.winner }] : []);
      this.notificationsSilenced = result.notifications_silenced || false;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * Toggle ticket status (draw or return)
   */
  @action
  async toggleTicket() {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this._isToggling = true;

    try {
      let result;
      if (this.hasTicket) {
        // Return ticket
        result = await ajax(`/vzekc-verlosung/tickets/${this.post.id}`, {
          type: "DELETE",
        });
      } else {
        // Draw ticket
        result = await ajax("/vzekc-verlosung/tickets", {
          type: "POST",
          data: { post_id: this.post.id },
        });
      }

      // Update local component state from API response
      this.hasTicket = result.has_ticket;
      this.ticketCount = result.ticket_count;
      this.users = result.users || [];
      // Support both old format (winner) and new format (winners array)
      this.winnersData =
        result.winners ||
        (result.winner ? [{ instance_number: 1, ...result.winner }] : []);

      // Update the cached post data so it persists across component recreation (scroll)
      if (this.post) {
        this.post.packet_ticket_status = {
          has_ticket: result.has_ticket,
          ticket_count: result.ticket_count,
          users: result.users || [],
          winners: this.winnersData,
        };

        // Also update the topic's lottery_packets cache (for lottery-intro-summary)
        // This ensures the cache is updated even if intro-summary is destroyed
        const topic = this.post.topic;
        if (topic?.lottery_packets) {
          const packetIndex = topic.lottery_packets.findIndex(
            (p) => p.post_id === this.post.id
          );
          if (packetIndex !== -1) {
            topic.lottery_packets[packetIndex] = {
              ...topic.lottery_packets[packetIndex],
              ticket_count: result.ticket_count,
              users: result.users || [],
            };
          }
        }
      }

      // Emit event to update other LIVE widgets on the page
      this.appEvents.trigger("lottery:ticket-changed", {
        postId: this.post.id,
        ticketCount: result.ticket_count,
        users: result.users || [],
        hasTicket: result.has_ticket,
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this._isToggling = false;
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
   * Check if user can draw or return tickets
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
   * Get the packet quantity
   *
   * @type {number}
   */
  get packetQuantity() {
    return this.post?.packet_quantity || 1;
  }

  /**
   * Check if this is a multi-instance packet (quantity > 1)
   *
   * @type {boolean}
   */
  get isMultiInstance() {
    return this.packetQuantity > 1;
  }

  /**
   * Get winners data array
   *
   * @type {Array}
   */
  get winners() {
    return this.winnersData;
  }

  /**
   * Check if packet has any winners
   *
   * @type {boolean}
   */
  get hasWinner() {
    return this.winnersData.length > 0;
  }

  /**
   * Get the first winner for this packet (for backward compatibility)
   *
   * @type {Object|null}
   */
  get winner() {
    return this.winnersData[0] || null;
  }

  /**
   * Get first winner username (for backward compatibility and Abholerpaket)
   *
   * @type {string|null}
   */
  get winnerUsername() {
    const winner = this.winner;
    if (!winner) {
      return null;
    }
    return winner.username;
  }

  /**
   * Check if first winner is a full user object with avatar_template
   *
   * @type {boolean}
   */
  get hasWinnerObject() {
    const winner = this.winner;
    return winner && winner.avatar_template;
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
   * Check if this is an Abholerpaket
   *
   * @type {boolean}
   */
  get isAbholerpaket() {
    return this.post?.is_abholerpaket === true;
  }

  /**
   * Check if current user is the lottery owner
   *
   * @type {boolean}
   */
  get isLotteryOwner() {
    const topic = this.post?.topic;
    return this.currentUser && topic && topic.user_id === this.currentUser.id;
  }

  /**
   * Check if notification toggle should be shown
   * Only show to lottery owner after lottery is drawn
   *
   * @type {boolean}
   */
  get showNotificationToggle() {
    return this.isLotteryOwner && this.isDrawn;
  }

  /**
   * Get the winner entry for the current user (if they are a winner)
   *
   * @type {Object|null}
   */
  get currentUserWinnerEntry() {
    if (!this.currentUser) {
      return null;
    }
    return this.winnersData.find(
      (w) => w.username === this.currentUser.username
    );
  }

  /**
   * Check if current user is a winner of this packet
   *
   * @type {boolean}
   */
  get isWinner() {
    return this.currentUserWinnerEntry != null;
  }

  /**
   * Check if Erhaltungsbericht is required for this packet
   *
   * @type {boolean}
   */
  get erhaltungsberichtRequired() {
    // Default to true if not explicitly set to false
    return this.post?.erhaltungsbericht_required !== false;
  }

  /**
   * Check if a winner entry can be collected (state is "won" or "shipped")
   *
   * @param {Object} winnerEntry
   * @returns {boolean}
   */
  isCollectable(winnerEntry) {
    return (
      winnerEntry?.fulfillment_state === "won" ||
      winnerEntry?.fulfillment_state === "shipped"
    );
  }

  /**
   * Check if a winner entry can be shipped (state is "won")
   *
   * @param {Object} winnerEntry
   * @returns {boolean}
   */
  isShippable(winnerEntry) {
    return winnerEntry?.fulfillment_state === "won";
  }

  /**
   * Check if current user can mark their instance as collected
   *
   * @type {boolean}
   */
  get canMarkAsCollected() {
    const entry = this.currentUserWinnerEntry;
    return (
      entry &&
      this.isCollectable(entry) &&
      !this.loading &&
      this.markingCollected === null
    );
  }

  /**
   * Check if current user can mark a specific winner entry as collected
   * Either the current user is that winner, or they are the lottery owner
   *
   * @param {Object} winnerEntry
   * @returns {boolean}
   */
  canMarkEntryAsCollected(winnerEntry) {
    if (!winnerEntry || !this.isCollectable(winnerEntry)) {
      return false;
    }
    if (this.loading || this.markingCollected !== null) {
      return false;
    }
    // Owner can mark any winner as collected
    if (this.isLotteryOwner) {
      return true;
    }
    // Winner can mark themselves as collected
    return (
      this.currentUser && winnerEntry.username === this.currentUser.username
    );
  }

  /**
   * Check if current user is this specific winner and can mark as collected
   * This is used to show "Erhalten" button only to the winner themselves
   *
   * @param {Object} winnerEntry
   * @returns {boolean}
   */
  canWinnerMarkAsCollected(winnerEntry) {
    if (!winnerEntry || !this.isCollectable(winnerEntry)) {
      return false;
    }
    if (this.loading || this.markingCollected !== null) {
      return false;
    }
    // Only show to this specific winner
    return (
      this.currentUser && winnerEntry.username === this.currentUser.username
    );
  }

  /**
   * Check if current user (lottery owner) can mark a specific winner entry as shipped
   * Only the lottery owner can mark entries as shipped, and only if they are not this winner
   *
   * @param {Object} winnerEntry
   * @returns {boolean}
   */
  canMarkEntryAsShipped(winnerEntry) {
    if (!winnerEntry || !this.isShippable(winnerEntry)) {
      return false;
    }
    if (this.loading || this.markingShipped !== null) {
      return false;
    }
    // Only owner can mark as shipped, but not if they are this winner
    if (!this.isLotteryOwner) {
      return false;
    }
    // Don't show shipped button if current user is this winner (they see "Erhalten" instead)
    const isThisWinner =
      this.currentUser && winnerEntry.username === this.currentUser.username;
    return !isThisWinner;
  }

  /**
   * Check if current user can create Erhaltungsbericht
   *
   * @type {boolean}
   */
  get canCreateErhaltungsbericht() {
    const entry = this.currentUserWinnerEntry;
    return this.canCreateErhaltungsberichtForEntry(entry);
  }

  /**
   * Check if current user can create Erhaltungsbericht for a specific winner entry
   *
   * @param {Object} winnerEntry
   * @returns {boolean}
   */
  canCreateErhaltungsberichtForEntry(winnerEntry) {
    if (!winnerEntry || this.loading) {
      return false;
    }
    // Only the winner themselves can create their report
    if (
      !this.currentUser ||
      winnerEntry.username !== this.currentUser.username
    ) {
      return false;
    }
    // Check if report is required
    if (!this.erhaltungsberichtRequired) {
      return false;
    }
    // Check if already has a report
    if (winnerEntry.erhaltungsbericht_topic_id) {
      return false;
    }
    // For Abholerpaket, don't require collection (creator already has it)
    if (this.isAbholerpaket) {
      return true;
    }
    // For regular packets, require collection first (state must be "received" or "completed")
    return (
      winnerEntry.fulfillment_state === "received" ||
      winnerEntry.fulfillment_state === "completed"
    );
  }

  /**
   * Get URL to current user's Erhaltungsbericht topic
   *
   * @type {string|null}
   */
  get erhaltungsberichtUrl() {
    const entry = this.currentUserWinnerEntry;
    if (!entry?.erhaltungsbericht_topic_id) {
      return null;
    }
    return `/t/${entry.erhaltungsbericht_topic_id}`;
  }

  /**
   * Format collected date for a winner entry
   *
   * @param {string} collectedAt
   * @returns {string|null}
   */
  formatCollectedDate(collectedAt) {
    if (!collectedAt) {
      return null;
    }
    const date = new Date(collectedAt);
    const locale = I18n.locale || "en";
    return date.toLocaleDateString(locale, {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  }

  /**
   * Mark a specific winner entry as collected (with confirmation)
   *
   * @param {Object} entry - The winner entry to mark as collected
   */
  @action
  async markEntryAsCollected(entry) {
    if (!entry || this.markingCollected !== null) {
      return;
    }

    const confirmed = await this.dialog.confirm({
      message: i18n("vzekc_verlosung.collection.confirm_message", {
        winner: entry.username,
        packet: this.packetTitle,
      }),
      didConfirm: () => true,
      didCancel: () => false,
    });

    if (!confirmed) {
      return;
    }

    this.markingCollected = entry.instance_number;

    try {
      const result = await ajax(
        `/vzekc-verlosung/packets/${this.post.id}/mark-collected`,
        {
          type: "POST",
          data: { instance_number: entry.instance_number },
        }
      );

      // Update local state with response
      const idx = this.winnersData.findIndex(
        (w) => w.instance_number === entry.instance_number
      );
      if (idx >= 0) {
        // Find the collected_at in the winners array from result
        const updatedWinner = result.winners?.find(
          (w) => w.instance_number === entry.instance_number
        );
        if (updatedWinner?.collected_at) {
          this.winnersData = [
            ...this.winnersData.slice(0, idx),
            {
              ...this.winnersData[idx],
              collected_at: updatedWinner.collected_at,
            },
            ...this.winnersData.slice(idx + 1),
          ];
        }
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.markingCollected = null;
    }
  }

  /**
   * Mark a specific winner entry as shipped (with tracking info modal)
   * Only lottery owner can do this
   *
   * @param {Object} entry - The winner entry to mark as shipped
   */
  @action
  markEntryAsShipped(entry) {
    if (!entry || this.markingShipped !== null) {
      return;
    }

    this.modal.show(MarkShippedModal, {
      model: {
        winnerUsername: entry.username,
        packetTitle: this.packetTitle,
        onConfirm: async (trackingInfo) => {
          await this._performMarkShipped(entry, trackingInfo);
        },
      },
    });
  }

  /**
   * Actually perform the mark as shipped API call
   *
   * @param {Object} entry - The winner entry to mark as shipped
   * @param {string|null} trackingInfo - Optional tracking information
   */
  async _performMarkShipped(entry, trackingInfo) {
    this.markingShipped = entry.instance_number;

    try {
      const result = await ajax(
        `/vzekc-verlosung/packets/${this.post.id}/mark-shipped`,
        {
          type: "POST",
          data: {
            instance_number: entry.instance_number,
            tracking_info: trackingInfo || null,
          },
        }
      );

      // Update local state with response
      const idx = this.winnersData.findIndex(
        (w) => w.instance_number === entry.instance_number
      );
      if (idx >= 0) {
        // Find the shipped_at in the winners array from result
        const updatedWinner = result.winners?.find(
          (w) => w.instance_number === entry.instance_number
        );
        if (updatedWinner?.shipped_at) {
          this.winnersData = [
            ...this.winnersData.slice(0, idx),
            { ...this.winnersData[idx], shipped_at: updatedWinner.shipped_at },
            ...this.winnersData.slice(idx + 1),
          ];
        }
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.markingShipped = null;
    }
  }

  /**
   * Mark a specific winner entry as handed over (sets both shipped and collected)
   * Only lottery owner can do this
   *
   * @param {Object} entry - The winner entry to mark as handed over
   */
  @action
  async markEntryAsHandedOver(entry) {
    if (!entry || this.markingShipped !== null) {
      return;
    }

    const confirmed = await this.dialog.confirm({
      message: i18n("vzekc_verlosung.handover.confirm_message", {
        winner: entry.username,
        packet: this.packetTitle,
      }),
      didConfirm: () => true,
      didCancel: () => false,
    });

    if (!confirmed) {
      return;
    }

    this.markingShipped = entry.instance_number;

    try {
      const result = await ajax(
        `/vzekc-verlosung/packets/${this.post.id}/mark-handed-over`,
        {
          type: "POST",
          data: { instance_number: entry.instance_number },
        }
      );

      // Update local state with response
      const idx = this.winnersData.findIndex(
        (w) => w.instance_number === entry.instance_number
      );
      if (idx >= 0) {
        const updatedWinner = result.winners?.find(
          (w) => w.instance_number === entry.instance_number
        );
        if (updatedWinner) {
          this.winnersData = [
            ...this.winnersData.slice(0, idx),
            {
              ...this.winnersData[idx],
              shipped_at: updatedWinner.shipped_at,
              collected_at: updatedWinner.collected_at,
            },
            ...this.winnersData.slice(idx + 1),
          ];
        }
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.markingShipped = null;
    }
  }

  /**
   * Mark current user's packet instance as collected (with confirmation)
   * @deprecated Use markEntryAsCollected instead
   */
  @action
  async markAsCollected() {
    const entry = this.currentUserWinnerEntry;
    if (entry) {
      await this.markEntryAsCollected(entry);
    }
  }

  /**
   * Toggle notifications silenced for this packet
   * Only lottery owner can toggle, and only after lottery is drawn
   */
  @action
  async toggleNotifications() {
    if (!this.isLotteryOwner || !this.isDrawn || this.loading) {
      return;
    }
    try {
      const result = await ajax(
        `/vzekc-verlosung/packets/${this.post.id}/toggle-notifications`,
        { type: "PUT" }
      );
      this.notificationsSilenced = result.notifications_silenced;
    } catch (error) {
      popupAjaxError(error);
    }
  }

  /**
   * Create Erhaltungsbericht topic for this packet
   * Opens the composer with pre-filled content and packet references
   * The packet_post_id, packet_topic_id, and winner_instance_number will be stored
   * as custom fields when the topic is created, allowing for a link back to the packet
   *
   * @param {Object} winnerEntry - Optional winner entry, defaults to current user's entry
   */
  @action
  createErhaltungsbericht(winnerEntry) {
    const entry = winnerEntry || this.currentUserWinnerEntry;
    if (!entry) {
      return;
    }

    // Get category and template
    const categoryId = parseInt(
      this.siteSettings.vzekc_verlosung_erhaltungsberichte_category_id,
      10
    );

    if (!categoryId) {
      this.dialog.alert(
        i18n("vzekc_verlosung.erhaltungsbericht.category_not_configured")
      );
      return;
    }

    // Compose topic title: "<packet-title> aus <lottery-title>"
    const packetTitle = this.packetTitle || `Paket #${this.post.post_number}`;
    const lotteryTitle = this.post.topic.title;
    const topicTitle = `${packetTitle} aus ${lotteryTitle}`;

    // Get template from site settings
    const template =
      this.siteSettings.vzekc_verlosung_erhaltungsbericht_template || "";

    // Open composer with pre-filled content and packet reference
    // Use unique draftKey with timestamp to prevent draft conflicts
    this.composer.open({
      action: Composer.CREATE_TOPIC,
      categoryId,
      title: topicTitle,
      reply: template,
      draftKey: `new_topic_erhaltungsbericht_${this.post.id}_${entry.instance_number}_${Date.now()}`,
      // These custom fields will be serialized to the topic
      // Keys must match first parameter of serializeToDraft in erhaltungsbericht-composer.js
      packet_post_id: this.post.id,
      packet_topic_id: this.post.topic_id,
      winner_instance_number: entry.instance_number,
      skipSimilarTopics: true,
    });
  }

  <template>
    {{#if this.shouldShow}}
      <div class="lottery-packet-status">
        {{! Show indicator if no Erhaltungsbericht required }}
        {{#unless this.erhaltungsberichtRequired}}
          <div class="no-erhaltungsbericht-notice">
            {{icon "ban"}}
            <span>{{i18n
                "vzekc_verlosung.erhaltungsbericht.not_required"
              }}</span>
          </div>
        {{/unless}}

        {{#if this.isDrawn}}
          {{! Lottery has been drawn - show winner(s) or no winner message }}
          {{#if this.hasWinner}}
            <div class="lottery-packet-winner-notice">
              {{#if this.isAbholerpaket}}
                {{! Abholerpaket - only show Erhaltungsbericht section }}
                <div class="abholerpaket-badge">
                  {{icon "box-archive"}}
                  <span>Abholerpaket</span>
                </div>
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
                {{#if this.erhaltungsberichtUrl}}
                  <div class="erhaltungsbericht-link-section">
                    <a
                      href={{this.erhaltungsberichtUrl}}
                      class="erhaltungsbericht-link"
                    >
                      {{icon "gift"}}
                      <span>{{i18n
                          "vzekc_verlosung.erhaltungsbericht.view_link"
                        }}</span>
                    </a>
                  </div>
                {{/if}}
              {{else}}
                {{! Regular packet - show full information }}
                {{#unless this.loading}}
                  <div class="participants-display">
                    <span class="participants-label">{{i18n
                        "vzekc_verlosung.ticket.participants"
                      }}:</span>
                    <TicketCountBadge
                      @count={{this.ticketCount}}
                      @users={{this.users}}
                      @packetTitle={{this.packetTitle}}
                    />
                  </div>
                {{/unless}}

                {{! Show winners list }}
                <div class="winners-section">
                  <span class="participants-label">{{i18n
                      "vzekc_verlosung.ticket.winner"
                    }}{{#if
                      this.isMultiInstance
                    }}({{this.winners.length}}/{{this.packetQuantity}}){{/if}}:</span>
                  <ul class="winners-list">
                    {{#each this.winners as |winnerEntry|}}
                      <li class="winner-entry">
                        {{#if this.isMultiInstance}}
                          <span
                            class="winner-instance"
                          >#{{winnerEntry.instance_number}}</span>
                        {{/if}}
                        {{#if winnerEntry.avatar_template}}
                          <UserLink
                            @username={{winnerEntry.username}}
                            class="winner-user-link"
                          >
                            {{avatar winnerEntry imageSize="small"}}
                            <span
                              class="winner-name"
                            >{{winnerEntry.username}}</span>
                          </UserLink>
                        {{else}}
                          <UserLink
                            @username={{winnerEntry.username}}
                            class="winner-user-link"
                          >
                            <span
                              class="winner-name"
                            >{{winnerEntry.username}}</span>
                          </UserLink>
                        {{/if}}
                        {{! Status text based on fulfillment_state }}
                        <span class="winner-status">
                          {{#if
                            (and
                              (eq winnerEntry.fulfillment_state "completed")
                              winnerEntry.erhaltungsbericht_topic_id
                            )
                          }}
                            <span class="status-finished">{{icon "file-lines"}}
                              {{i18n "vzekc_verlosung.status.finished"}}</span>
                          {{else if
                            (or
                              (eq winnerEntry.fulfillment_state "received")
                              (eq winnerEntry.fulfillment_state "completed")
                            )
                          }}
                            <span
                              class="status-collected"
                              title={{if
                                winnerEntry.collected_at
                                (i18n
                                  "vzekc_verlosung.collection.collected_on"
                                  date=(this.formatCollectedDate
                                    winnerEntry.collected_at
                                  )
                                )
                              }}
                            >{{icon "check"}}
                              {{i18n "vzekc_verlosung.status.collected"}}</span>
                          {{else if
                            (eq winnerEntry.fulfillment_state "shipped")
                          }}
                            <span
                              class="status-shipped"
                              title={{if
                                winnerEntry.shipped_at
                                (i18n
                                  "vzekc_verlosung.shipping.shipped_on"
                                  date=(this.formatCollectedDate
                                    winnerEntry.shipped_at
                                  )
                                )
                              }}
                            >{{icon "paper-plane"}}
                              {{i18n "vzekc_verlosung.status.shipped"}}</span>
                          {{else}}
                            <span class="status-won">{{icon "trophy"}}
                              {{i18n "vzekc_verlosung.status.won"}}</span>
                          {{/if}}
                        </span>
                        {{! Action button (right-aligned) }}
                        <span class="winner-action">
                          {{#if (this.canWinnerMarkAsCollected winnerEntry)}}
                            <DButton
                              @action={{fn
                                this.markEntryAsCollected
                                winnerEntry
                              }}
                              @icon="check"
                              @label="vzekc_verlosung.collection.received"
                              @disabled={{this.markingCollected}}
                              class="btn-small btn-default mark-collected-inline-button"
                              title={{i18n
                                "vzekc_verlosung.collection.mark_collected"
                              }}
                            />
                          {{else if (this.canMarkEntryAsShipped winnerEntry)}}
                            <DButton
                              @action={{fn this.markEntryAsShipped winnerEntry}}
                              @icon="paper-plane"
                              @label="vzekc_verlosung.shipping.shipped"
                              @disabled={{this.markingShipped}}
                              class="btn-small btn-default mark-shipped-inline-button"
                              title={{i18n
                                "vzekc_verlosung.shipping.mark_shipped"
                              }}
                            />
                            <DButton
                              @action={{fn
                                this.markEntryAsHandedOver
                                winnerEntry
                              }}
                              @icon="handshake"
                              @label="vzekc_verlosung.handover.handed_over"
                              @disabled={{this.markingShipped}}
                              class="btn-small btn-default mark-handed-over-inline-button"
                              title={{i18n
                                "vzekc_verlosung.handover.mark_handed_over"
                              }}
                            />
                          {{/if}}
                        </span>
                        {{#if winnerEntry.erhaltungsbericht_topic_id}}
                          <a
                            href="/t/{{winnerEntry.erhaltungsbericht_topic_id}}"
                            class="winner-bericht-link"
                            title={{i18n
                              "vzekc_verlosung.erhaltungsbericht.view_link"
                            }}
                          >{{icon "file-lines"}}</a>
                        {{else if
                          (this.canCreateErhaltungsberichtForEntry winnerEntry)
                        }}
                          <DButton
                            @action={{fn
                              this.createErhaltungsbericht
                              winnerEntry
                            }}
                            @icon="pen"
                            @label="vzekc_verlosung.erhaltungsbericht.create_button"
                            class="btn-small btn-primary create-erhaltungsbericht-inline-button"
                          />
                        {{/if}}
                        {{#if
                          (and
                            this.isLotteryOwner winnerEntry.winner_pm_topic_id
                          )
                        }}
                          <a
                            href="/t/{{winnerEntry.winner_pm_topic_id}}"
                            class="winner-pm-link"
                            title={{i18n "vzekc_verlosung.winner_pm.view_link"}}
                          >{{icon "envelope"}}</a>
                        {{/if}}
                      </li>
                    {{/each}}
                  </ul>
                </div>

                {{! Notification toggle for lottery owner }}
                {{#if this.showNotificationToggle}}
                  <div class="notification-toggle-row">
                    <DButton
                      @action={{this.toggleNotifications}}
                      @icon={{if
                        this.notificationsSilenced
                        "bell-slash"
                        "bell"
                      }}
                      @title={{if
                        this.notificationsSilenced
                        (i18n "vzekc_verlosung.notifications.unmute_packet")
                        (i18n "vzekc_verlosung.notifications.mute_packet")
                      }}
                      class="btn-flat notification-toggle-button"
                    />
                  </div>
                {{/if}}
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
          {{! Lottery is active - show draw/return button or Abholerpaket message }}
          <div class="lottery-packet-active-notice">
            {{#if this.isAbholerpaket}}
              <div class="abholerpaket-info">
                <span class="abholerpaket-label">
                  {{icon "box-archive"}}
                  {{i18n "vzekc_verlosung.ticket.abholerpaket"}}
                </span>
                <p class="abholerpaket-message">
                  {{i18n
                    "vzekc_verlosung.ticket.abholerpaket_description"
                    username=this.winnerUsername
                  }}
                </p>
              </div>
              {{#if this.canCreateErhaltungsbericht}}
                <div class="action-section">
                  <DButton
                    @action={{this.createErhaltungsbericht}}
                    @label="vzekc_verlosung.erhaltungsbericht.create_button"
                    @icon="pen"
                    class="btn-primary create-erhaltungsbericht-button"
                  />
                </div>
              {{/if}}
              {{#if this.erhaltungsberichtUrl}}
                <div class="erhaltungsbericht-link-section">
                  <a
                    href={{this.erhaltungsberichtUrl}}
                    class="erhaltungsbericht-link"
                  >
                    {{icon "gift"}}
                    <span>{{i18n
                        "vzekc_verlosung.erhaltungsbericht.view_link"
                      }}</span>
                  </a>
                </div>
              {{/if}}
            {{else}}
              <div class="action-section">
                <DButton
                  @action={{this.toggleTicket}}
                  @label={{this.buttonLabel}}
                  @icon={{this.buttonIcon}}
                  @disabled={{this.loading}}
                  class="btn-primary lottery-ticket-button"
                />
              </div>
              <div class="participants-display">
                <span class="participants-label">{{i18n
                    "vzekc_verlosung.ticket.participants"
                  }}:</span>
                <TicketCountBadge
                  @count={{this.ticketCount}}
                  @users={{this.users}}
                  @packetTitle={{this.packetTitle}}
                />
              </div>
            {{/if}}
          </div>
        {{else if this.hasEnded}}
          {{! Lottery has ended but not drawn yet }}
          <div class="lottery-packet-ended-notice">
            {{#if this.isAbholerpaket}}
              <div class="abholerpaket-info">
                <span class="abholerpaket-label">
                  {{icon "box-archive"}}
                  {{i18n "vzekc_verlosung.ticket.abholerpaket"}}
                </span>
                <p class="abholerpaket-message">
                  {{i18n
                    "vzekc_verlosung.ticket.abholerpaket_description"
                    username=this.winnerUsername
                  }}
                </p>
              </div>
              {{#if this.canCreateErhaltungsbericht}}
                <div class="action-section">
                  <DButton
                    @action={{this.createErhaltungsbericht}}
                    @label="vzekc_verlosung.erhaltungsbericht.create_button"
                    @icon="pen"
                    class="btn-primary create-erhaltungsbericht-button"
                  />
                </div>
              {{/if}}
              {{#if this.erhaltungsberichtUrl}}
                <div class="erhaltungsbericht-link-section">
                  <a
                    href={{this.erhaltungsberichtUrl}}
                    class="erhaltungsbericht-link"
                  >
                    {{icon "gift"}}
                    <span>{{i18n
                        "vzekc_verlosung.erhaltungsbericht.view_link"
                      }}</span>
                  </a>
                </div>
              {{/if}}
            {{else}}
              {{#unless this.loading}}
                <div class="participants-display">
                  <span class="participants-label">{{i18n
                      "vzekc_verlosung.ticket.participants"
                    }}:</span>
                  <TicketCountBadge
                    @count={{this.ticketCount}}
                    @users={{this.users}}
                    @packetTitle={{this.packetTitle}}
                    @hasEnded={{true}}
                  />
                </div>
              {{/unless}}
            {{/if}}
          </div>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
