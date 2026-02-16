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
import { and, eq, or } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import TicketCountBadge from "./ticket-count-badge";

/**
 * Lottery widget component combining ticket button and count display
 *
 * @component LotteryWidget
 * Shows a button to draw/return lottery tickets and displays the ticket count with participants.
 * For drawn lotteries, shows only participants and winner identity (fulfillment management
 * is handled in lottery-intro-summary).
 *
 * @param {Object} args.data.post - The post object (passed via renderGlimmer)
 */
export default class LotteryWidget extends Component {
  @service currentUser;
  @service appEvents;
  @service packetFulfillment;

  @tracked hasTicket = false;
  @tracked ticketCount = 0;
  @tracked users = [];
  @tracked winnersData = [];
  @tracked loading = true;
  @tracked markingCollected = false;
  @tracked markingShipped = false;
  @tracked notificationsSilenced = false;

  constructor() {
    super(...arguments);

    if (this.shouldShow) {
      this.loadTicketDataFromPost();
      this.appEvents.on("lottery:ticket-changed", this, this.onTicketChanged);
      this.appEvents.on(
        "lottery:fulfillment-changed",
        this,
        this.onFulfillmentChanged
      );
      document.addEventListener("visibilitychange", this.onVisibilityChange);
    } else {
      this.loading = false;
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    if (this.shouldShow) {
      this.appEvents.off("lottery:ticket-changed", this, this.onTicketChanged);
      this.appEvents.off(
        "lottery:fulfillment-changed",
        this,
        this.onFulfillmentChanged
      );
      document.removeEventListener("visibilitychange", this.onVisibilityChange);
    }
  }

  @bind
  onVisibilityChange() {
    if (!document.hidden && this.shouldShow) {
      this.loadTicketDataFromAjax();
    }
  }

  /**
   * @type {Object}
   */
  get post() {
    return this.args.data?.post;
  }

  @bind
  onTicketChanged(eventData) {
    if (eventData.postId === this.post?.id && !this._isToggling) {
      this.hasTicket = eventData.hasTicket;
      this.ticketCount = eventData.ticketCount;
      this.users = eventData.users || [];

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

  @bind
  onFulfillmentChanged(eventData) {
    if (eventData.postId === this.post?.id && eventData.winners) {
      this.winnersData = eventData.winners;
    }
  }

  /**
   * Load ticket data from serialized post data (no AJAX request)
   */
  loadTicketDataFromPost() {
    try {
      const status = this.post?.packet_ticket_status;
      if (status) {
        this.hasTicket = status.has_ticket || false;
        this.ticketCount = status.ticket_count || 0;
        this.users = status.users || [];
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
   * Reload ticket data via AJAX (only when page becomes visible)
   */
  async loadTicketDataFromAjax() {
    try {
      const result = await ajax(
        `/vzekc-verlosung/tickets/packet-status/${this.post.id}`
      );
      this.hasTicket = result.has_ticket;
      this.ticketCount = result.ticket_count;
      this.users = result.users || [];
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
        result = await ajax(`/vzekc-verlosung/tickets/${this.post.id}`, {
          type: "DELETE",
        });
      } else {
        result = await ajax("/vzekc-verlosung/tickets", {
          type: "POST",
          data: { post_id: this.post.id },
        });
      }

      this.hasTicket = result.has_ticket;
      this.ticketCount = result.ticket_count;
      this.users = result.users || [];
      this.winnersData =
        result.winners ||
        (result.winner ? [{ instance_number: 1, ...result.winner }] : []);

      if (this.post) {
        this.post.packet_ticket_status = {
          has_ticket: result.has_ticket,
          ticket_count: result.ticket_count,
          users: result.users || [],
          winners: this.winnersData,
        };

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
   * @type {boolean}
   */
  get shouldShow() {
    return this.currentUser && this.post?.is_lottery_packet;
  }

  /**
   * @type {boolean}
   */
  get canBuyOrReturn() {
    const topic = this.post?.topic;
    if (topic?.lottery_state !== "active") {
      return false;
    }
    if (topic?.lottery_ends_at) {
      const endsAt = new Date(topic.lottery_ends_at);
      if (endsAt <= new Date()) {
        return false;
      }
    }
    return true;
  }

  /**
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
   * @type {boolean}
   */
  get isDrawn() {
    const topic = this.post?.topic;
    return topic?.lottery_results != null;
  }

  /**
   * @type {number}
   */
  get packetQuantity() {
    return this.post?.packet_quantity || 1;
  }

  /**
   * @type {boolean}
   */
  get isMultiInstance() {
    return this.packetQuantity > 1;
  }

  /**
   * @type {Array}
   */
  get winners() {
    return this.winnersData;
  }

  /**
   * @type {boolean}
   */
  get hasWinner() {
    return this.winnersData.length > 0;
  }

  /**
   * @type {Object|null}
   */
  get winner() {
    return this.winnersData[0] || null;
  }

  /**
   * @type {string|null}
   */
  get winnerUsername() {
    return this.winner?.username || null;
  }

  /**
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
   * @type {string}
   */
  get buttonIcon() {
    return this.hasTicket ? "xmark" : "gift";
  }

  /**
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
   * @type {boolean}
   */
  get isAbholerpaket() {
    return this.post?.is_abholerpaket === true;
  }

  /**
   * @type {boolean}
   */
  get erhaltungsberichtRequired() {
    return this.post?.erhaltungsbericht_required !== false;
  }

  /**
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
   * @type {boolean}
   */
  get canCreateErhaltungsbericht() {
    return this.packetFulfillment.canCreateErhaltungsberichtForEntry(
      this.currentUserWinnerEntry,
      {
        isAbholerpaket: this.isAbholerpaket,
        erhaltungsberichtRequired: this.erhaltungsberichtRequired,
      }
    );
  }

  /**
   * @type {string|null}
   */
  get erhaltungsberichtUrl() {
    const entry = this.currentUserWinnerEntry;
    if (!entry?.erhaltungsbericht_topic_id) {
      return null;
    }
    return `/t/${entry.erhaltungsbericht_topic_id}`;
  }

  @action
  createErhaltungsbericht() {
    const entry = this.currentUserWinnerEntry;
    if (!entry) {
      return;
    }
    this.packetFulfillment.createErhaltungsbericht(entry, {
      post: this.post,
      packetTitle: this.packetTitle,
    });
  }

  /**
   * @type {boolean}
   */
  get isSinglePacketMode() {
    return this.post?.topic?.lottery_packet_mode === "ein";
  }

  /**
   * @type {boolean}
   */
  get isLotteryOwner() {
    return (
      this.currentUser && this.post?.topic?.user_id === this.currentUser.id
    );
  }

  /**
   * Check if this winner entry can be marked as collected by the winner
   *
   * @param {Object} winnerEntry
   * @returns {boolean}
   */
  @action
  canWinnerMarkAsCollectedForEntry(winnerEntry) {
    return this.packetFulfillment.canWinnerMarkAsCollected(winnerEntry, {
      isActionInProgress: this.markingCollected || this.markingShipped,
    });
  }

  /**
   * Check if this winner entry can be marked as shipped by the lottery owner
   *
   * @param {Object} winnerEntry
   * @returns {boolean}
   */
  @action
  canMarkEntryAsShippedForEntry(winnerEntry) {
    return this.packetFulfillment.canMarkEntryAsShipped(winnerEntry, {
      isLotteryOwner: this.isLotteryOwner,
      isActionInProgress: this.markingCollected || this.markingShipped,
    });
  }

  /**
   * Check if current user can create Erhaltungsbericht for a specific winner entry
   *
   * @param {Object} winnerEntry
   * @returns {boolean}
   */
  @action
  canCreateErhaltungsberichtForEntry(winnerEntry) {
    return this.packetFulfillment.canCreateErhaltungsberichtForEntry(
      winnerEntry,
      {
        isAbholerpaket: this.isAbholerpaket,
        erhaltungsberichtRequired: this.erhaltungsberichtRequired,
      }
    );
  }

  @action
  async handleMarkCollected(winnerEntry) {
    if (this.markingCollected || this.markingShipped) {
      return;
    }

    this.markingCollected = true;
    try {
      const result = await this.packetFulfillment.markEntryAsCollected(
        this.post.id,
        winnerEntry,
        { packetTitle: this.packetTitle }
      );
      if (result?.winners) {
        this.winnersData = result.winners;
        this.appEvents.trigger("lottery:fulfillment-changed", {
          postId: this.post.id,
          winners: result.winners,
        });
      }
    } finally {
      this.markingCollected = false;
    }
  }

  @action
  handleMarkShipped(winnerEntry) {
    if (this.markingCollected || this.markingShipped) {
      return;
    }

    this.markingShipped = true;
    this.packetFulfillment.markEntryAsShipped(this.post.id, winnerEntry, {
      packetTitle: this.packetTitle,
      onComplete: (result) => {
        if (result?.winners) {
          this.winnersData = result.winners;
          this.appEvents.trigger("lottery:fulfillment-changed", {
            postId: this.post.id,
            winners: result.winners,
          });
        }
        this.markingShipped = false;
      },
    });
  }

  @action
  async handleMarkHandedOver(winnerEntry) {
    if (this.markingCollected || this.markingShipped) {
      return;
    }

    this.markingShipped = true;
    try {
      const result = await this.packetFulfillment.markEntryAsHandedOver(
        this.post.id,
        winnerEntry,
        { packetTitle: this.packetTitle }
      );
      if (result?.winners) {
        this.winnersData = result.winners;
        this.appEvents.trigger("lottery:fulfillment-changed", {
          postId: this.post.id,
          winners: result.winners,
        });
      }
    } finally {
      this.markingShipped = false;
    }
  }

  @action
  async handleToggleNotifications() {
    const result = await this.packetFulfillment.toggleNotifications(
      this.post.id
    );
    if (result) {
      this.notificationsSilenced = result.notifications_silenced;
    }
  }

  @action
  createErhaltungsberichtForEntry(winnerEntry) {
    this.packetFulfillment.createErhaltungsbericht(winnerEntry, {
      post: this.post,
      packetTitle: this.packetTitle,
    });
  }

  <template>
    {{#if this.shouldShow}}
      <div class="lottery-packet-status">
        {{#unless this.erhaltungsberichtRequired}}
          <div class="no-erhaltungsbericht-notice">
            {{icon "ban"}}
            <span>{{i18n
                "vzekc_verlosung.erhaltungsbericht.not_required"
              }}</span>
          </div>
        {{/unless}}

        {{#if this.isDrawn}}
          {{#if this.hasWinner}}
            <div class="lottery-packet-winner-notice">
              {{#if this.isAbholerpaket}}
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
              {{else if this.isSinglePacketMode}}
                {{! Single-packet mode: full fulfillment UI here since intro summary doesn't show packets }}
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

                <div class="packet-winners-fulfillment">
                  {{#each this.winners as |winnerEntry|}}
                    <div class="packet-winner-row">
                      <span class="packet-winner-identity">
                        {{#if this.isMultiInstance}}
                          <span
                            class="winner-instance"
                          >#{{winnerEntry.instance_number}}</span>
                        {{/if}}
                        <UserLink
                          @username={{winnerEntry.username}}
                          class="winner-user-link"
                        >
                          {{avatar winnerEntry imageSize="tiny"}}
                          <span
                            class="winner-name"
                          >{{winnerEntry.username}}</span>
                        </UserLink>
                      </span>

                      {{! Status badge }}
                      <span class="winner-fulfillment-status">
                        {{#if
                          (and
                            (eq winnerEntry.fulfillment_state "completed")
                            winnerEntry.erhaltungsbericht_topic_id
                          )
                        }}
                          <span class="status-badge status-finished">{{icon
                              "file-lines"
                            }}
                            {{i18n "vzekc_verlosung.status.finished"}}</span>
                        {{else if
                          (or
                            (eq winnerEntry.fulfillment_state "received")
                            (eq winnerEntry.fulfillment_state "completed")
                          )
                        }}
                          <span
                            class="status-badge status-collected"
                            title={{if
                              winnerEntry.collected_at
                              (i18n
                                "vzekc_verlosung.collection.collected_on"
                                date=(this.packetFulfillment.formatCollectedDate
                                  winnerEntry.collected_at
                                )
                              )
                            }}
                          >{{icon "check"}}
                            {{i18n "vzekc_verlosung.status.collected"}}</span>
                        {{else if (eq winnerEntry.fulfillment_state "shipped")}}
                          <span
                            class="status-badge status-shipped"
                            title={{if
                              winnerEntry.shipped_at
                              (i18n
                                "vzekc_verlosung.shipping.shipped_on"
                                date=(this.packetFulfillment.formatCollectedDate
                                  winnerEntry.shipped_at
                                )
                              )
                            }}
                          >{{icon "paper-plane"}}
                            {{i18n "vzekc_verlosung.status.shipped"}}</span>
                        {{else}}
                          <span class="status-badge status-won">{{icon
                              "trophy"
                            }}
                            {{i18n "vzekc_verlosung.status.won"}}</span>
                        {{/if}}
                      </span>

                      {{! Action buttons }}
                      <span class="winner-fulfillment-actions">
                        {{#if
                          (this.canWinnerMarkAsCollectedForEntry winnerEntry)
                        }}
                          <DButton
                            @action={{fn this.handleMarkCollected winnerEntry}}
                            @icon="check"
                            @label="vzekc_verlosung.collection.received"
                            @disabled={{this.markingCollected}}
                            class="btn-small btn-default mark-collected-inline-button"
                            title={{i18n
                              "vzekc_verlosung.collection.mark_collected"
                            }}
                          />
                        {{else if
                          (this.canMarkEntryAsShippedForEntry winnerEntry)
                        }}
                          <DButton
                            @action={{fn this.handleMarkShipped winnerEntry}}
                            @icon="paper-plane"
                            @label="vzekc_verlosung.shipping.shipped"
                            @disabled={{this.markingShipped}}
                            class="btn-small btn-default mark-shipped-inline-button"
                            title={{i18n
                              "vzekc_verlosung.shipping.mark_shipped"
                            }}
                          />
                          <DButton
                            @action={{fn this.handleMarkHandedOver winnerEntry}}
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

                      {{! Links }}
                      <span class="winner-fulfillment-links">
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
                              this.createErhaltungsberichtForEntry
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
                      </span>
                    </div>
                  {{/each}}

                  {{! Notification toggle for lottery owner }}
                  {{#if this.isLotteryOwner}}
                    <div class="packet-notification-toggle">
                      <DButton
                        @action={{this.handleToggleNotifications}}
                        @icon={{if
                          this.notificationsSilenced
                          "bell-slash"
                          "bell"
                        }}
                        @title={{if
                          this.notificationsSilenced
                          "vzekc_verlosung.notifications.unmute_packet"
                          "vzekc_verlosung.notifications.mute_packet"
                        }}
                        class="btn-flat notification-toggle-button"
                      />
                    </div>
                  {{/if}}
                </div>
              {{else}}
                {{! Multi-packet mode: simplified view, fulfillment is in intro summary }}
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
                      </li>
                    {{/each}}
                  </ul>
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
