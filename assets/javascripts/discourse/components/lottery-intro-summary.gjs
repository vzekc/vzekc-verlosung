import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { registerDestructor } from "@ember/destroyable";
import { concat, fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import UserLink from "discourse/components/user-link";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import { and, eq, gt, or } from "discourse/truth-helpers";
import I18n, { i18n } from "discourse-i18n";
import DrawLotteryModal from "./modal/draw-lottery-modal";
import TicketCountBadge from "./ticket-count-badge";

/**
 * Component to display lottery packet summary on lottery intro posts
 *
 * @component LotteryIntroSummary
 * Shows a list of lottery packets with their ticket counts
 *
 * @param {Object} data.post - The lottery intro post object
 */
export default class LotteryIntroSummary extends Component {
  @service currentUser;
  @service appEvents;
  @service modal;
  @service siteSettings;
  @service lotteryDisplayMode;

  @tracked packets = [];
  @tracked loading = true;
  @tracked publishing = false;
  @tracked ending = false;
  @tracked openingDrawModal = false;
  @tracked resultsCopied = false;
  @tracked now = new Date();

  _timer = null;

  constructor() {
    super(...arguments);
    // Load from serialized/cached topic data (updated when tickets change)
    this.loadPacketsFromTopic();
    this.appEvents.on("lottery:ticket-changed", this, this.onTicketChanged);
    this._startTimer();
    registerDestructor(this, () => this._stopTimer());
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.appEvents.off("lottery:ticket-changed", this, this.onTicketChanged);
  }

  _startTimer() {
    this._timer = setInterval(() => {
      this.now = new Date();
    }, 1000);
  }

  _stopTimer() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
    }
  }

  @bind
  onTicketChanged(eventData) {
    // Find the packet that changed
    const packetIndex = this.packets.findIndex(
      (p) => p.post_id === eventData.postId
    );
    if (packetIndex === -1) {
      return;
    }

    // Update the packet data in our local array
    const updatedPackets = [...this.packets];
    updatedPackets[packetIndex] = {
      ...updatedPackets[packetIndex],
      ticket_count: eventData.ticketCount,
      users: eventData.users || [],
    };
    this.packets = updatedPackets;

    // Update the cached topic data so it persists across component recreation
    const topic = this.args.data.post.topic;
    if (topic?.lottery_packets) {
      const topicPacketIndex = topic.lottery_packets.findIndex(
        (p) => p.post_id === eventData.postId
      );
      if (topicPacketIndex !== -1) {
        topic.lottery_packets[topicPacketIndex] = {
          ...topic.lottery_packets[topicPacketIndex],
          ticket_count: eventData.ticketCount,
          users: eventData.users || [],
        };
      }
    }
  }

  /**
   * Load packets from serialized topic data (no AJAX request)
   */
  loadPacketsFromTopic() {
    try {
      // Packets are already serialized in the topic data
      this.packets = this.args.data.post.topic?.lottery_packets || [];
    } finally {
      this.loading = false;
    }
  }

  /**
   * Reload packets via AJAX (only when tickets change)
   */
  async loadPacketsFromAjax() {
    try {
      const result = await ajax(
        `/vzekc-verlosung/lotteries/${this.args.data.post.topic_id}/packets`
      );
      this.packets = result.packets || [];
    } catch (error) {
      popupAjaxError(error);
    }
  }

  /**
   * Get the topic object
   *
   * @returns {Object} the topic object
   */
  get topic() {
    return this.args.data.post.topic;
  }

  /**
   * Check if this lottery is a draft
   *
   * @returns {Boolean} true if the lottery is in draft state
   */
  get isDraft() {
    return this.topic?.lottery_state === "draft";
  }

  /**
   * Check if this lottery is active
   *
   * @returns {Boolean} true if the lottery is active
   */
  get isActive() {
    return this.topic?.lottery_state === "active";
  }

  /**
   * Check if lottery is active and still running (not ended yet)
   *
   * @returns {Boolean} true if the lottery is active and hasn't ended
   */
  get isRunning() {
    if (!this.isActive || !this.topic?.lottery_ends_at) {
      return false;
    }
    const endsAt = new Date(this.topic.lottery_ends_at);
    const now = new Date();
    return endsAt > now;
  }

  /**
   * Check if this lottery is finished
   *
   * @returns {Boolean} true if the lottery is finished
   */
  get isFinished() {
    return this.topic?.lottery_state === "finished";
  }

  /**
   * Check if lottery has downloadable results (finished with actual winners)
   *
   * @returns {Boolean} true if results can be downloaded
   */
  get hasDownloadableResults() {
    if (!this.isFinished) {
      return false;
    }
    const results = this.topic?.lottery_results;
    // No results or marked as no_participants means no downloadable results
    return results && !results.no_participants;
  }

  /**
   * Get the packet mode for this lottery
   *
   * @returns {String} "ein" or "mehrere" (default: "mehrere")
   */
  get packetMode() {
    return this.topic?.lottery_packet_mode || "mehrere";
  }

  /**
   * Check if lottery has ended
   *
   * @returns {Boolean} true if the lottery has ended
   */
  get hasEnded() {
    if (!this.topic?.lottery_ends_at) {
      return false;
    }
    const endsAt = new Date(this.topic.lottery_ends_at);
    return endsAt <= this.now;
  }

  /**
   * Get the end date as Date object
   *
   * @returns {Date|null} the end date
   */
  get endDate() {
    if (!this.topic?.lottery_ends_at) {
      return null;
    }
    return new Date(this.topic.lottery_ends_at);
  }

  /**
   * Format the end date and time display
   * Format depends on display mode:
   * - Absolute: "Endet am <datum> um <uhrzeit> (<verbleibende zeit>)"
   * - Relative: "<verbleibende zeit> (am <datum> um <uhrzeit>)"
   * When ended: "Wartet auf Ziehung (Endete am <datum> um <uhrzeit>)"
   *
   * @returns {String} formatted end date/time string with relative time
   */
  get endDateTimeDisplay() {
    if (!this.endDate) {
      return "";
    }

    const dateStr = this.endDate.toLocaleDateString("de-DE", {
      day: "numeric",
      month: "long",
      year: "numeric",
    });

    const timeStr = this.endDate.toLocaleTimeString("de-DE", {
      hour: "2-digit",
      minute: "2-digit",
    });

    if (this.hasEnded) {
      return `Wartet auf Ziehung (Endete am ${dateStr} um ${timeStr})`;
    }

    const relativeTime = this.relativeTimeRemaining;

    if (this.lotteryDisplayMode.isAbsoluteMode) {
      return `Endet am ${dateStr} um ${timeStr} (${relativeTime})`;
    } else {
      return `${relativeTime} (am ${dateStr} um ${timeStr})`;
    }
  }

  /**
   * Get relative time remaining
   *
   * @returns {String} relative time string
   */
  get relativeTimeRemaining() {
    if (!this.endDate) {
      return "";
    }

    const diffMs = this.endDate - this.now;

    if (diffMs <= 0) {
      return i18n("vzekc_verlosung.status.ended");
    }

    const diffSeconds = Math.floor(diffMs / 1000);
    const diffMinutes = Math.floor(diffSeconds / 60);
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays >= 1) {
      const remainingHours = diffHours % 24;
      if (diffDays === 1 && remainingHours === 1) {
        return i18n("vzekc_verlosung.status.one_day_one_hour_remaining");
      } else if (diffDays === 1) {
        return i18n("vzekc_verlosung.status.one_day_hours_remaining", {
          hours: remainingHours,
        });
      } else if (remainingHours === 1) {
        return i18n("vzekc_verlosung.status.days_one_hour_remaining", {
          days: diffDays,
        });
      }
      return i18n("vzekc_verlosung.status.days_hours_remaining", {
        days: diffDays,
        hours: remainingHours,
      });
    } else if (diffHours > 1) {
      return i18n("vzekc_verlosung.status.hours_remaining", {
        count: diffHours,
      });
    } else if (diffHours === 1) {
      return i18n("vzekc_verlosung.status.one_hour_remaining");
    } else if (diffMinutes > 5) {
      return i18n("vzekc_verlosung.status.minutes_remaining", {
        count: diffMinutes,
      });
    } else if (diffMinutes >= 1) {
      const remainingSeconds = diffSeconds % 60;
      if (diffMinutes === 1 && remainingSeconds === 1) {
        return i18n("vzekc_verlosung.status.one_minute_one_second_remaining");
      } else if (diffMinutes === 1) {
        return i18n("vzekc_verlosung.status.one_minute_seconds_remaining", {
          seconds: remainingSeconds,
        });
      } else if (remainingSeconds === 1) {
        return i18n("vzekc_verlosung.status.minutes_one_second_remaining", {
          minutes: diffMinutes,
        });
      }
      return i18n("vzekc_verlosung.status.minutes_seconds_remaining", {
        minutes: diffMinutes,
        seconds: remainingSeconds,
      });
    } else if (diffSeconds > 1) {
      return i18n("vzekc_verlosung.status.seconds_remaining", {
        count: diffSeconds,
      });
    } else {
      return i18n("vzekc_verlosung.status.one_second_remaining");
    }
  }

  /**
   * Check if lottery has ended but not been drawn yet
   *
   * @returns {Boolean} true if ready to draw
   */
  get canDraw() {
    if (!this.topic || !this.topic.lottery_ends_at) {
      return false;
    }
    const hasEnded = new Date(this.topic.lottery_ends_at) <= new Date();
    const notDrawn = !this.topic.lottery_results;
    return hasEnded && notDrawn && this.canPublish;
  }

  /**
   * Check if the lottery has an end date set
   *
   * @returns {Boolean} true if end date is set
   */
  get hasEndsAt() {
    return !!this.topic?.lottery_ends_at;
  }

  /**
   * Check if current user can publish this lottery
   *
   * @returns {Boolean} true if user can publish
   */
  get canPublish() {
    if (!this.currentUser) {
      return false;
    }
    return this.args.data.post.user_id === this.currentUser.id;
  }

  /**
   * Check if current user is the lottery owner
   *
   * @returns {Boolean} true if user is lottery owner
   */
  get isLotteryOwner() {
    return (
      this.currentUser &&
      this.topic &&
      this.topic.user_id === this.currentUser.id
    );
  }

  /**
   * Check if current user has a ticket for a specific packet
   *
   * @param {Object} packet - The packet to check
   * @returns {Boolean} true if user has a ticket for this packet
   */
  @action
  userHasTicket(packet) {
    if (!this.currentUser || !packet.users) {
      return false;
    }
    return packet.users.some((user) => user.id === this.currentUser.id);
  }

  /**
   * Check if end early button should be shown
   *
   * @returns {Boolean} true if button should be shown
   */
  get showEndEarlyButton() {
    return this.siteSettings.vzekc_verlosung_show_end_early_button;
  }

  /**
   * Get regular packets (excluding Abholerpaket)
   *
   * @type {Array}
   */
  get regularPackets() {
    return this.packets.filter((p) => !p.abholerpaket);
  }

  /**
   * Get total number of participants across all packets
   *
   * @type {number}
   */
  get totalParticipants() {
    const uniqueUserIds = new Set();
    this.packets.forEach((packet) => {
      if (packet.users) {
        packet.users.forEach((user) => uniqueUserIds.add(user.id));
      }
    });
    return uniqueUserIds.size;
  }

  /**
   * Get total number of tickets across all packets
   *
   * @type {number}
   */
  get totalTickets() {
    return this.packets.reduce(
      (sum, packet) => sum + (packet.ticket_count || 0),
      0
    );
  }

  /**
   * Get number of regular packets without any tickets
   *
   * @type {number}
   */
  get packetsWithoutTickets() {
    return this.regularPackets.filter(
      (p) => !p.ticket_count || p.ticket_count === 0
    ).length;
  }

  /**
   * Format collected date for display
   *
   * @param {String|Date} collectedAt - The collection timestamp
   * @returns {String} formatted date string
   */
  formatCollectedDate(collectedAt) {
    if (!collectedAt) {
      return null;
    }
    const date = new Date(collectedAt);
    // Use user's locale from Discourse
    const locale = I18n.locale || "en";
    return date.toLocaleDateString(locale, {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  }

  /**
   * Get the publish button label
   *
   * @returns {String} the button label
   */
  get publishButtonLabel() {
    return this.publishing
      ? i18n("vzekc_verlosung.draft.publishing")
      : i18n("vzekc_verlosung.draft.publish_button");
  }

  /**
   * Get the publish button icon
   *
   * @returns {String} the button icon
   */
  get publishButtonIcon() {
    return this.publishing ? "spinner" : "paper-plane";
  }

  /**
   * Publish the lottery (remove draft status)
   */
  @action
  async publishLottery() {
    if (this.publishing) {
      return;
    }

    this.publishing = true;
    try {
      await ajax(
        `/vzekc-verlosung/lotteries/${this.args.data.post.topic_id}/publish`,
        {
          type: "PUT",
        }
      );
      // Reload to clean URL (strip any query parameters that might hide posts)
      const cleanUrl = window.location.pathname;
      window.location.href = cleanUrl;
    } catch (error) {
      popupAjaxError(error);
      this.publishing = false;
    }
  }

  /**
   * Open the drawing modal to draw winners
   */
  @action
  async drawWinners() {
    this.openingDrawModal = true;
    try {
      await this.modal.show(DrawLotteryModal, {
        model: {
          topicId: this.args.data.post.topic_id,
        },
      });
    } finally {
      // Reset spinner state when modal closes (whether cancelled or completed)
      this.openingDrawModal = false;
    }
  }

  /**
   * End the lottery early (for testing purposes)
   */
  @action
  async endEarly() {
    if (this.ending) {
      return;
    }

    // eslint-disable-next-line no-alert
    if (!confirm(i18n("vzekc_verlosung.testing.end_early_confirm"))) {
      return;
    }

    this.ending = true;
    try {
      await ajax(
        `/vzekc-verlosung/lotteries/${this.args.data.post.topic_id}/end-early`,
        {
          type: "PUT",
        }
      );
      // Reload the page to show the ended state
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
      this.ending = false;
    }
  }

  /**
   * Get packets with winners resolved from lottery results JSON
   *
   * @returns {Array} packets with winnerUsername from results JSON
   */
  get packetsWithWinners() {
    const results = this.topic?.lottery_results;
    const regularPackets = this.packets.filter((p) => !p.abholerpaket);

    if (!results?.drawings || !results?.packets) {
      // No results JSON or missing data, fall back to database winners
      return regularPackets;
    }

    // Match packets by post_id using index correspondence between
    // results.packets and results.drawings arrays
    return regularPackets.map((packet) => {
      // Find the index of this packet in the results.packets array by post_id
      const resultIndex = results.packets.findIndex(
        (p) => p.id === packet.post_id
      );

      if (resultIndex >= 0 && results.drawings[resultIndex]) {
        const drawing = results.drawings[resultIndex];
        return {
          ...packet,
          winnerUsername: drawing.winner,
        };
      }

      // Fallback to database winner
      return {
        ...packet,
        winnerUsername: packet.winner?.username,
      };
    });
  }

  /**
   * Download lottery results as CSV file
   * Format: packet number; packet name; winner nickname
   */
  @action
  downloadResultsCsv() {
    const packetsWithWinners = this.packetsWithWinners.filter(
      (p) => p.winnerUsername
    );

    // Build CSV content with semicolon separator
    const header = "Paket-Nr;Paketname;Gewinner";
    const rows = packetsWithWinners.map(
      (packet) =>
        `${packet.ordinal};"${packet.title.replace(/"/g, '""')}";"${packet.winnerUsername}"`
    );
    const csvContent = [header, ...rows].join("\n");

    // Create blob and download
    const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);

    const link = document.createElement("a");
    link.setAttribute("href", url);
    link.setAttribute("download", `lottery-${this.topic.id}-results.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  /**
   * Copy lottery results to clipboard
   * Format: #<packet no> <packet title>: @<winner> <celebratory emoji>
   * Packets without tickets show "keine Lose gezogen"
   */
  @action
  async copyResultsToClipboard() {
    const celebratoryEmojis = [
      "🎉",
      "🎊",
      "🥳",
      "🏆",
      "⭐",
      "🌟",
      "✨",
      "🎈",
      "🎁",
      "👏",
    ];

    const lines = this.packetsWithWinners.map((packet) => {
      if (packet.winnerUsername) {
        const emoji =
          celebratoryEmojis[
            Math.floor(Math.random() * celebratoryEmojis.length)
          ];
        return `#${packet.ordinal} ${packet.title}: @${packet.winnerUsername} ${emoji}`;
      } else {
        return `#${packet.ordinal} ${packet.title}: keine Lose gezogen`;
      }
    });

    // Add link to lottery at the end
    const lotteryUrl = `${window.location.origin}${this.topic.url}`;
    lines.push("");
    lines.push(`Details zur Verlosung: ${lotteryUrl}`);

    const text = lines.join("\n");

    try {
      await navigator.clipboard.writeText(text);
      this.resultsCopied = true;
      setTimeout(() => {
        this.resultsCopied = false;
      }, 2000);
    } catch {
      // Fallback for older browsers
      const textarea = document.createElement("textarea");
      textarea.value = text;
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      document.body.removeChild(textarea);
      this.resultsCopied = true;
      setTimeout(() => {
        this.resultsCopied = false;
      }, 2000);
    }
  }

  /**
   * Open Erhaltungsbericht composer for Abholerpaket
   *
   * @param {Object} packet - The Abholerpaket object
   */
  @action
  openErhaltungsberichtComposer(packet) {
    if (!packet) {
      return;
    }

    const lottery = this.topic;
    const packetTitle = packet.title;
    const erhaltungsberichtTitle = `${packetTitle} aus ${lottery.title}`;

    // Get template from site settings
    const template =
      this.siteSettings.vzekc_verlosung_erhaltungsbericht_template || "";

    // CRITICAL: Category SiteSettings are strings, must parse to integer
    const categoryId = parseInt(
      this.siteSettings.vzekc_verlosung_erhaltungsberichte_category_id,
      10
    );

    // Abholerpaket now has a post, use same mechanism as regular packets
    this.appEvents.trigger("composer:open", {
      action: "createTopic",
      title: erhaltungsberichtTitle,
      body: template,
      categoryId,
      packet_post_id: packet.post_id,
      packet_topic_id: lottery.id,
    });
  }

  <template>
    <div class="lottery-intro-summary">
      {{#if this.loading}}
        <div class="lottery-intro-loading">
          {{icon "spinner" class="fa-spin"}}
        </div>
      {{else}}
        {{#if this.isDraft}}
          {{#if this.canPublish}}
            <div class="lottery-draft-notice">
              <div class="draft-message">
                {{icon "lock"}}
                <span>{{i18n "vzekc_verlosung.draft.notice"}}</span>
              </div>
              <DButton
                @action={{this.publishLottery}}
                @translatedLabel={{this.publishButtonLabel}}
                @icon={{this.publishButtonIcon}}
                @disabled={{this.publishing}}
                @isLoading={{this.publishing}}
                class="btn-primary lottery-publish-button"
              />
            </div>
          {{/if}}
        {{/if}}

        {{#if this.isActive}}
          {{#if this.hasEndsAt}}
            <div class="lottery-active-notice">
              <div class="active-message">
                {{icon "clock"}}
                <span>{{i18n "vzekc_verlosung.state.active"}}</span>
              </div>
              <div class="time-remaining">
                {{this.endDateTimeDisplay}}
              </div>
              <div class="lottery-status-line">
                {{#if (gt this.regularPackets.length 1)}}
                  <span class="status-item">
                    {{icon "cube"}}
                    {{this.regularPackets.length}}
                    {{i18n "vzekc_verlosung.status.packets"}}
                  </span>
                {{/if}}
                {{#if (gt this.totalParticipants 0)}}
                  <span class="status-item">
                    {{icon "users"}}
                    {{this.totalParticipants}}
                    {{i18n "vzekc_verlosung.status.participants"}}
                  </span>
                {{/if}}
                {{#if (gt this.totalTickets 0)}}
                  <span class="status-item">
                    {{icon "ticket"}}
                    {{this.totalTickets}}
                    {{i18n "vzekc_verlosung.status.tickets"}}
                  </span>
                {{/if}}
                {{#if (gt this.packetsWithoutTickets 0)}}
                  <span class="status-item warning">
                    {{icon "ban"}}
                    {{this.packetsWithoutTickets}}
                    {{i18n "vzekc_verlosung.status.without_tickets"}}
                  </span>
                {{/if}}
              </div>
              {{#if
                (and this.isRunning this.canPublish this.showEndEarlyButton)
              }}
                <DButton
                  @action={{this.endEarly}}
                  @translatedLabel={{if
                    this.ending
                    (i18n "vzekc_verlosung.testing.ending")
                    (i18n "vzekc_verlosung.testing.end_early_button")
                  }}
                  @icon={{if this.ending "spinner" "forward"}}
                  @disabled={{this.ending}}
                  @isLoading={{this.ending}}
                  class="btn-danger btn-small lottery-end-early-button"
                />
              {{/if}}
            </div>
          {{/if}}
        {{/if}}

        {{#if this.canDraw}}
          <div class="lottery-draw-notice">
            <div class="draw-message">
              {{icon "trophy"}}
              <span>{{i18n
                  "vzekc_verlosung.drawing.ready"
                  mode=(i18n
                    (concat
                      "vzekc_verlosung.drawing.mode_"
                      (or this.topic.lottery_drawing_mode "automatic")
                    )
                  )
                }}</span>
            </div>
            <DButton
              @action={{this.drawWinners}}
              @translatedLabel={{i18n "vzekc_verlosung.drawing.draw_button"}}
              @icon={{if this.openingDrawModal "spinner" "dice"}}
              @disabled={{this.openingDrawModal}}
              @isLoading={{this.openingDrawModal}}
              class="btn-primary lottery-draw-button"
            />
          </div>
        {{/if}}

        {{#if this.isFinished}}
          <div class="lottery-finished-notice">
            <div class="finished-message">
              {{icon "circle-check"}}
              <span>{{i18n "vzekc_verlosung.state.finished"}}</span>
            </div>
            {{#if this.hasDownloadableResults}}
              <div class="download-results">
                <span class="download-label">{{i18n
                    "vzekc_verlosung.drawing.download_results_label"
                  }}</span>
                <a
                  href="/vzekc-verlosung/lotteries/{{this.topic.id}}/results.json"
                  class="btn btn-default btn-small"
                  download
                  title={{i18n
                    "vzekc_verlosung.drawing.download_results_json_help"
                  }}
                >
                  {{icon "download"}}
                  {{i18n "vzekc_verlosung.drawing.download_results_json"}}
                </a>
                <DButton
                  @action={{this.downloadResultsCsv}}
                  @translatedLabel={{i18n
                    "vzekc_verlosung.drawing.download_results_csv"
                  }}
                  @translatedTitle={{i18n
                    "vzekc_verlosung.drawing.download_results_csv_help"
                  }}
                  @icon="download"
                  class="btn-default btn-small"
                />
                <DButton
                  @action={{this.copyResultsToClipboard}}
                  @translatedLabel={{if
                    this.resultsCopied
                    (i18n "vzekc_verlosung.drawing.copy_results_copied")
                    (i18n "vzekc_verlosung.drawing.copy_results")
                  }}
                  @translatedTitle={{i18n
                    "vzekc_verlosung.drawing.copy_results_help"
                  }}
                  @icon={{if this.resultsCopied "check" "copy"}}
                  class="btn-default btn-small"
                />
              </div>
            {{/if}}
          </div>
        {{/if}}

        {{! ========== PACKETS LIST ========== }}
        {{! Only show packet list in "mehrere" mode - in "ein" mode, the main post is the packet }}
        {{#if (and this.packets.length (eq this.packetMode "mehrere"))}}
          <h3 class="lottery-packets-title">{{i18n
              "vzekc_verlosung.packets_title"
            }}</h3>
          <ul class="lottery-packets-list">
            {{#each this.packets as |packet|}}
              <li
                class={{concat
                  "lottery-packet-item"
                  (if (this.userHasTicket packet) " user-has-ticket")
                }}
              >
                <span class="packet-ordinal">{{packet.ordinal}}:</span>
                <a
                  href="/t/{{this.topic.id}}/{{packet.post_number}}"
                  class="packet-title"
                >{{packet.title}}</a>

                {{! Show indicator if no Erhaltungsbericht required }}
                {{#unless packet.erhaltungsbericht_required}}
                  <span
                    class="no-erhaltungsbericht-indicator"
                    title={{i18n
                      "vzekc_verlosung.erhaltungsbericht.not_required"
                    }}
                  >
                    {{icon "ban"}}
                  </span>
                {{/unless}}

                {{#if packet.abholerpaket}}
                  {{! Abholerpaket - show label instead of ticket count }}
                  <span class="abholerpaket-label">{{i18n
                      "vzekc_verlosung.ticket.abholerpaket"
                    }}</span>

                  {{! Show Erhaltungsbericht controls only to lottery owner }}
                  {{#if this.isLotteryOwner}}
                    {{#if packet.erhaltungsbericht_topic_id}}
                      <a
                        href="/t/{{packet.erhaltungsbericht_topic_id}}"
                        class="erhaltungsbericht-link"
                      >
                        {{icon "gift"}}
                        {{i18n "vzekc_verlosung.erhaltungsbericht.view_link"}}
                      </a>
                    {{else if packet.erhaltungsbericht_required}}
                      <DButton
                        @action={{fn this.openErhaltungsberichtComposer packet}}
                        @label="vzekc_verlosung.erhaltungsbericht.create_button"
                        @icon="pen"
                        class="btn-small btn-primary erhaltungsbericht-create-btn"
                      />
                    {{/if}}
                  {{/if}}
                {{else}}
                  {{! Regular packet - show winner or ticket count }}
                  {{#if this.isFinished}}
                    {{#if packet.winner}}
                      <span class="packet-winner">
                        <span class="participants-label">{{i18n
                            "vzekc_verlosung.ticket.winner"
                          }}:</span>
                        <UserLink
                          @username={{packet.winner.username}}
                          class="winner-user-link"
                        >
                          {{avatar packet.winner imageSize="tiny"}}
                          <span
                            class="winner-name"
                          >{{packet.winner.username}}</span>
                        </UserLink>
                        {{#if (this.showCollectionIndicatorForPacket packet)}}
                          <span class="collection-indicator collected">
                            {{icon "check"}}
                            <span
                              class="collection-date"
                            >{{this.formatCollectedDate
                                packet.collected_at
                              }}</span>
                          </span>
                        {{/if}}
                      </span>
                    {{else}}
                      <span class="packet-no-tickets">
                        {{i18n "vzekc_verlosung.ticket.no_tickets"}}
                      </span>
                    {{/if}}
                  {{else}}
                    <TicketCountBadge
                      @count={{packet.ticket_count}}
                      @users={{packet.users}}
                      @packetTitle={{packet.title}}
                      @hasEnded={{this.hasEnded}}
                    />
                  {{/if}}
                {{/if}}
              </li>
            {{/each}}
          </ul>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
