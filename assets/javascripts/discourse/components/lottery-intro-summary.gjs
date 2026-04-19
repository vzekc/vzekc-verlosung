import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { registerDestructor } from "@ember/destroyable";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import DiscourseURL from "discourse/lib/url";
import { and, gt, or } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import DrawLotteryModal from "./modal/draw-lottery-modal";
import ResetLotteryModal from "./modal/reset-lottery-modal";

/**
 * Component to display lottery status notices on lottery intro posts
 *
 * @component LotteryIntroSummary
 * Shows draft/active/draw/finished notices with status info and action buttons.
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
  @tracked openingResetModal = false;
  @tracked resultsCopied = false;
  @tracked now = new Date();

  _timer = null;

  constructor() {
    super(...arguments);
    this.loadPacketsFromTopic();
    this.appEvents.on("lottery:ticket-changed", this, this.onTicketChanged);
    this.appEvents.on(
      "lottery:fulfillment-changed",
      this,
      this.onFulfillmentChanged
    );
    this._startTimer();
    registerDestructor(this, () => this._stopTimer());
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.appEvents.off("lottery:ticket-changed", this, this.onTicketChanged);
    this.appEvents.off(
      "lottery:fulfillment-changed",
      this,
      this.onFulfillmentChanged
    );
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
    const packetIndex = this.packets.findIndex(
      (p) => p.post_id === eventData.postId
    );
    if (packetIndex === -1) {
      return;
    }

    const updatedPackets = [...this.packets];
    updatedPackets[packetIndex] = {
      ...updatedPackets[packetIndex],
      ticket_count: eventData.ticketCount,
      users: eventData.users || [],
    };
    this.packets = updatedPackets;

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

  @bind
  onFulfillmentChanged(eventData) {
    if (!eventData.postId || !eventData.winners) {
      return;
    }
    const packetIndex = this.packets.findIndex(
      (p) => p.post_id === eventData.postId
    );
    if (packetIndex === -1) {
      return;
    }

    const updatedPackets = [...this.packets];
    updatedPackets[packetIndex] = {
      ...updatedPackets[packetIndex],
      winners: eventData.winners,
    };
    this.packets = updatedPackets;
  }

  /**
   * Load packets from serialized topic data (no AJAX request)
   */
  loadPacketsFromTopic() {
    try {
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
   * @returns {Object} the topic object
   */
  get topic() {
    return this.args.data.post.topic;
  }

  /**
   * @returns {Boolean} true if the lottery is in draft state
   */
  get isDraft() {
    return this.topic?.lottery_state === "draft";
  }

  /**
   * @returns {Boolean} true if the lottery is active
   */
  get isActive() {
    return this.topic?.lottery_state === "active";
  }

  /**
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
   * @returns {Boolean} true if the lottery is finished
   */
  get isFinished() {
    return this.topic?.lottery_state === "finished";
  }

  /**
   * @returns {Boolean} true if results can be downloaded
   */
  get hasDownloadableResults() {
    if (!this.isFinished) {
      return false;
    }
    const results = this.topic?.lottery_results;
    return results && !results.no_participants;
  }

  /**
   * @returns {Boolean} true if the lottery ended without any participants
   */
  get isNoParticipants() {
    if (!this.isFinished) {
      return false;
    }
    return this.topic?.lottery_results?.no_participants === true;
  }

  /**
   * @returns {Boolean} true if the current user can relist this lottery
   */
  get canReset() {
    return this.isNoParticipants && this.canPublish;
  }

  /**
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
   * @returns {Date|null} the end date
   */
  get endDate() {
    if (!this.topic?.lottery_ends_at) {
      return null;
    }
    return new Date(this.topic.lottery_ends_at);
  }

  /**
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
   * @returns {Boolean} true if ready to draw
   */
  get canDraw() {
    if (!this.topic || !this.topic.lottery_ends_at) {
      return false;
    }
    const hasEndedNow = new Date(this.topic.lottery_ends_at) <= new Date();
    const notDrawn = !this.topic.lottery_results;
    return hasEndedNow && notDrawn && this.canPublish;
  }

  /**
   * @returns {Boolean} true if end date is set
   */
  get hasEndsAt() {
    return !!this.topic?.lottery_ends_at;
  }

  /**
   * @returns {Boolean} true if user can publish
   */
  get canPublish() {
    if (!this.currentUser) {
      return false;
    }
    return this.args.data.post.user_id === this.currentUser.id;
  }

  /**
   * @returns {Boolean} true if button should be shown
   */
  get showEndEarlyButton() {
    return this.siteSettings.vzekc_verlosung_show_end_early_button;
  }

  /**
   * @type {Array}
   */
  get regularPackets() {
    return this.packets.filter((p) => !p.abholerpaket);
  }

  /**
   * @returns {Array|null} current user's tickets with won/lost state (when finished) or just titles (when active)
   */
  get currentUserTickets() {
    if (!this.currentUser) {
      return null;
    }
    const userId = this.currentUser.id;
    const myPackets = this.regularPackets.filter((p) =>
      p.users?.some((u) => u.id === userId)
    );
    if (myPackets.length === 0) {
      return null;
    }
    return myPackets.map((packet) => {
      const result = {
        title: packet.title,
        postNumber: packet.post_number,
      };
      if (this.isFinished) {
        result.won = packet.winners?.some((w) => w.id === userId) ?? false;
      }
      return result;
    });
  }

  /**
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
   * @type {number}
   */
  get totalTickets() {
    return this.packets.reduce(
      (sum, packet) => sum + (packet.ticket_count || 0),
      0
    );
  }

  /**
   * @type {number}
   */
  get packetsWithoutTickets() {
    return this.regularPackets.filter(
      (p) => !p.ticket_count || p.ticket_count === 0
    ).length;
  }

  /**
   * @returns {String} the button label
   */
  get publishButtonLabel() {
    return this.publishing
      ? i18n("vzekc_verlosung.draft.publishing")
      : i18n("vzekc_verlosung.draft.publish_button");
  }

  /**
   * @returns {String} the button icon
   */
  get publishButtonIcon() {
    return this.publishing ? "spinner" : "paper-plane";
  }

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
      const cleanUrl = window.location.pathname;
      window.location.href = cleanUrl;
    } catch (error) {
      popupAjaxError(error);
      this.publishing = false;
    }
  }

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
      this.openingDrawModal = false;
    }
  }

  @action
  async resetLottery() {
    this.openingResetModal = true;
    try {
      await this.modal.show(ResetLotteryModal, {
        model: {
          topicId: this.args.data.post.topic_id,
          defaultDurationDays: this.topic?.lottery_duration_days || 14,
        },
      });
    } finally {
      this.openingResetModal = false;
    }
  }

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
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
      this.ending = false;
    }
  }

  /**
   * Get packets with winners resolved from lottery results JSON
   *
   * @returns {Array} packets with winners array from results JSON
   */
  get packetsWithWinners() {
    const results = this.topic?.lottery_results;
    const regularPackets = this.packets.filter((p) => !p.abholerpaket);

    if (!results?.drawings || !results?.packets) {
      return regularPackets;
    }

    return regularPackets.map((packet) => {
      const resultIndex = results.packets.findIndex(
        (p) => p.id === packet.post_id
      );

      if (resultIndex >= 0 && results.drawings[resultIndex]) {
        const drawing = results.drawings[resultIndex];
        const winners =
          drawing.winners || (drawing.winner ? [drawing.winner] : []);
        return {
          ...packet,
          winnerUsernames: winners,
          winnerUsername: winners[0] || null,
        };
      }

      const dbWinners =
        packet.winners || (packet.winner ? [packet.winner] : []);
      return {
        ...packet,
        winnerUsernames: dbWinners.map((w) => w.username),
        winnerUsername: dbWinners[0]?.username || null,
      };
    });
  }

  @action
  downloadResultsCsv() {
    const packetsWithWinners = this.packetsWithWinners.filter(
      (p) => p.winnerUsernames?.length > 0 || p.winnerUsername
    );

    const header = "Paket-Nr;Paketname;Instanz;Gewinner";
    const rows = [];

    packetsWithWinners.forEach((packet) => {
      const winners =
        packet.winnerUsernames ||
        (packet.winnerUsername ? [packet.winnerUsername] : []);
      const quantity = packet.quantity || 1;

      winners.forEach((winner, index) => {
        const instanceNum = quantity > 1 ? index + 1 : "";
        const title =
          quantity > 1 ? `${quantity}x ${packet.title}` : packet.title;
        rows.push(
          `${packet.ordinal};"${title.replace(/"/g, '""')}";${instanceNum};"${winner}"`
        );
      });
    });

    const csvContent = [header, ...rows].join("\n");
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
      const winners =
        packet.winnerUsernames ||
        (packet.winnerUsername ? [packet.winnerUsername] : []);
      const quantity = packet.quantity || 1;
      const title =
        quantity > 1 ? `${quantity}x ${packet.title}` : packet.title;

      if (winners.length > 0) {
        const emoji =
          celebratoryEmojis[
            Math.floor(Math.random() * celebratoryEmojis.length)
          ];
        const winnerMentions = winners.map((w) => `@${w}`).join(", ");
        return `#${packet.ordinal} ${title}: ${winnerMentions} ${emoji}`;
      } else {
        return `#${packet.ordinal} ${title}: keine Lose gezogen`;
      }
    });

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

  @action
  goToPacket(postNumber, event) {
    event.preventDefault();
    history.replaceState(
      history.state,
      "",
      location.pathname + "#your-tickets"
    );
    history.pushState(history.state, "", location.pathname);
    DiscourseURL.jumpToPost(postNumber);
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
            {{#if this.canReset}}
              <div class="lottery-reset-notice">
                <p>{{i18n "vzekc_verlosung.reset_lottery.description"}}</p>
                <DButton
                  @action={{this.resetLottery}}
                  @translatedLabel={{i18n
                    "vzekc_verlosung.reset_lottery.button"
                  }}
                  @icon={{if this.openingResetModal "spinner" "rotate"}}
                  @disabled={{this.openingResetModal}}
                  @isLoading={{this.openingResetModal}}
                  class="btn-primary lottery-reset-button"
                />
              </div>
            {{/if}}
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

        {{#if this.currentUserTickets}}
          <div id="your-tickets" class="lottery-your-tickets">
            <div class="your-tickets-header">
              {{icon "ticket"}}
              <span>{{i18n "vzekc_verlosung.your_tickets.title"}}</span>
            </div>
            {{#each this.currentUserTickets as |entry|}}
              {{#if this.isFinished}}
                <div class="your-ticket {{if entry.won 'won' 'lost'}}">
                  <a
                    href={{concat "#post_" entry.postNumber}}
                    {{on "click" (fn this.goToPacket entry.postNumber)}}
                  >{{entry.title}}</a>
                </div>
              {{else}}
                <div class="your-ticket">
                  <a
                    href={{concat "#post_" entry.postNumber}}
                    {{on "click" (fn this.goToPacket entry.postNumber)}}
                  >{{entry.title}}</a>
                </div>
              {{/if}}
            {{/each}}
          </div>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
