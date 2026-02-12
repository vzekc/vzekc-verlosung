import Service, { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import Composer from "discourse/models/composer";
import I18n, { i18n } from "discourse-i18n";
import MarkShippedModal from "../components/modal/mark-shipped-modal";

/**
 * Service for packet fulfillment actions and permission checks.
 * Shared between lottery-widget and lottery-intro-summary.
 *
 * @service packetFulfillment
 */
export default class PacketFulfillmentService extends Service {
  @service dialog;
  @service modal;
  @service currentUser;
  @service siteSettings;
  @service composer;

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
   * Check if a winner entry can be marked as collected.
   * Either the current user is that winner, or they are the lottery owner.
   *
   * @param {Object} winnerEntry
   * @param {Object} opts
   * @param {boolean} opts.isLotteryOwner
   * @param {boolean} opts.isActionInProgress
   * @returns {boolean}
   */
  canMarkEntryAsCollected(
    winnerEntry,
    { isLotteryOwner = false, isActionInProgress = false } = {}
  ) {
    if (!winnerEntry || !this.isCollectable(winnerEntry)) {
      return false;
    }
    if (isActionInProgress) {
      return false;
    }
    if (isLotteryOwner) {
      return true;
    }
    return (
      this.currentUser && winnerEntry.username === this.currentUser.username
    );
  }

  /**
   * Check if current user is this specific winner and can mark as collected.
   * Used to show "Erhalten" button only to the winner themselves.
   *
   * @param {Object} winnerEntry
   * @param {Object} opts
   * @param {boolean} opts.isActionInProgress
   * @returns {boolean}
   */
  canWinnerMarkAsCollected(winnerEntry, { isActionInProgress = false } = {}) {
    if (!winnerEntry || !this.isCollectable(winnerEntry)) {
      return false;
    }
    if (isActionInProgress) {
      return false;
    }
    return (
      this.currentUser && winnerEntry.username === this.currentUser.username
    );
  }

  /**
   * Check if current user (lottery owner) can mark a winner entry as shipped.
   * Only the lottery owner can mark entries as shipped, and not if they are that winner.
   *
   * @param {Object} winnerEntry
   * @param {Object} opts
   * @param {boolean} opts.isLotteryOwner
   * @param {boolean} opts.isActionInProgress
   * @returns {boolean}
   */
  canMarkEntryAsShipped(
    winnerEntry,
    { isLotteryOwner = false, isActionInProgress = false } = {}
  ) {
    if (!winnerEntry || !this.isShippable(winnerEntry)) {
      return false;
    }
    if (isActionInProgress) {
      return false;
    }
    if (!isLotteryOwner) {
      return false;
    }
    const isThisWinner =
      this.currentUser && winnerEntry.username === this.currentUser.username;
    return !isThisWinner;
  }

  /**
   * Check if current user can create Erhaltungsbericht for a specific winner entry
   *
   * @param {Object} winnerEntry
   * @param {Object} opts
   * @param {boolean} opts.isAbholerpaket
   * @param {boolean} opts.erhaltungsberichtRequired
   * @returns {boolean}
   */
  canCreateErhaltungsberichtForEntry(
    winnerEntry,
    { isAbholerpaket = false, erhaltungsberichtRequired = true } = {}
  ) {
    if (!winnerEntry) {
      return false;
    }
    if (
      !this.currentUser ||
      winnerEntry.username !== this.currentUser.username
    ) {
      return false;
    }
    if (!erhaltungsberichtRequired) {
      return false;
    }
    if (winnerEntry.erhaltungsbericht_topic_id) {
      return false;
    }
    if (isAbholerpaket) {
      return true;
    }
    return (
      winnerEntry.fulfillment_state === "received" ||
      winnerEntry.fulfillment_state === "completed"
    );
  }

  /**
   * Mark a specific winner entry as collected (with confirmation dialog)
   *
   * @param {number} postId
   * @param {Object} entry - The winner entry
   * @param {Object} opts
   * @param {string} opts.packetTitle
   * @returns {Promise<Object|null>} API response or null if cancelled/failed
   */
  async markEntryAsCollected(postId, entry, { packetTitle } = {}) {
    if (!entry) {
      return null;
    }

    const confirmed = await this.dialog.confirm({
      message: i18n("vzekc_verlosung.collection.confirm_message", {
        winner: entry.username,
        packet: packetTitle,
      }),
      didConfirm: () => true,
      didCancel: () => false,
    });

    if (!confirmed) {
      return null;
    }

    try {
      return await ajax(`/vzekc-verlosung/packets/${postId}/mark-collected`, {
        type: "POST",
        data: { instance_number: entry.instance_number },
      });
    } catch (error) {
      popupAjaxError(error);
      return null;
    }
  }

  /**
   * Mark a specific winner entry as shipped (with tracking info modal).
   * Uses a callback since the modal is asynchronous.
   *
   * @param {number} postId
   * @param {Object} entry - The winner entry
   * @param {Object} opts
   * @param {string} opts.packetTitle
   * @param {Function} opts.onComplete - Called with API result or null
   */
  markEntryAsShipped(postId, entry, { packetTitle, onComplete } = {}) {
    if (!entry) {
      return;
    }

    this.modal.show(MarkShippedModal, {
      model: {
        winnerUsername: entry.username,
        packetTitle,
        onConfirm: async (trackingInfo) => {
          try {
            const result = await ajax(
              `/vzekc-verlosung/packets/${postId}/mark-shipped`,
              {
                type: "POST",
                data: {
                  instance_number: entry.instance_number,
                  tracking_info: trackingInfo || null,
                },
              }
            );
            onComplete?.(result);
          } catch (error) {
            popupAjaxError(error);
            onComplete?.(null);
          }
        },
      },
    });
  }

  /**
   * Mark a specific winner entry as handed over (with confirmation dialog)
   *
   * @param {number} postId
   * @param {Object} entry - The winner entry
   * @param {Object} opts
   * @param {string} opts.packetTitle
   * @returns {Promise<Object|null>} API response or null if cancelled/failed
   */
  async markEntryAsHandedOver(postId, entry, { packetTitle } = {}) {
    if (!entry) {
      return null;
    }

    const confirmed = await this.dialog.confirm({
      message: i18n("vzekc_verlosung.handover.confirm_message", {
        winner: entry.username,
        packet: packetTitle,
      }),
      didConfirm: () => true,
      didCancel: () => false,
    });

    if (!confirmed) {
      return null;
    }

    try {
      return await ajax(`/vzekc-verlosung/packets/${postId}/mark-handed-over`, {
        type: "POST",
        data: { instance_number: entry.instance_number },
      });
    } catch (error) {
      popupAjaxError(error);
      return null;
    }
  }

  /**
   * Toggle notifications silenced for a packet
   *
   * @param {number} postId
   * @returns {Promise<Object|null>} API response or null on failure
   */
  async toggleNotifications(postId) {
    try {
      return await ajax(
        `/vzekc-verlosung/packets/${postId}/toggle-notifications`,
        { type: "PUT" }
      );
    } catch (error) {
      popupAjaxError(error);
      return null;
    }
  }

  /**
   * Open composer to create Erhaltungsbericht for a winner entry
   *
   * @param {Object} entry - The winner entry
   * @param {Object} opts
   * @param {Object} opts.post - The packet post
   * @param {string} opts.packetTitle
   */
  createErhaltungsbericht(entry, { post, packetTitle }) {
    if (!entry) {
      return;
    }

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

    const title = packetTitle || `Paket #${post.post_number}`;
    const lotteryTitle = post.topic.title;
    const topicTitle = `${title} aus ${lotteryTitle}`;
    const template =
      this.siteSettings.vzekc_verlosung_erhaltungsbericht_template || "";

    this.composer.open({
      action: Composer.CREATE_TOPIC,
      categoryId,
      title: topicTitle,
      reply: template,
      draftKey: `new_topic_erhaltungsbericht_${post.id}_${entry.instance_number}_${Date.now()}`,
      packet_post_id: post.id,
      packet_topic_id: post.topic_id,
      winner_instance_number: entry.instance_number,
      skipSimilarTopics: true,
    });
  }

  /**
   * Format a date string for display
   *
   * @param {string} dateStr - ISO date string
   * @returns {string|null} formatted date or null
   */
  formatCollectedDate(dateStr) {
    if (!dateStr) {
      return null;
    }
    const date = new Date(dateStr);
    const locale = I18n.locale || "en";
    return date.toLocaleDateString(locale, {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  }
}
