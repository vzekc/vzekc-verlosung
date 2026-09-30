import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import LeaderboardDetailsModal from "./modal/leaderboard-details-modal";

/**
 * Displays leaderboards for lottery creators, ticket participants, winners, luck,
 * and uncollected wins
 *
 * @component LotteryLeaderboard
 * @param {string} @period - Look-back period ("3m", "6m", "1y" or "all")
 */
export default class LotteryLeaderboard extends Component {
  @service modal;

  @tracked leaderboard = null;
  @tracked isLoading = true;
  @tracked expandedInfo = null;

  constructor() {
    super(...arguments);
    this.loadLeaderboard();
    this.handleDocumentClick = this.handleDocumentClick.bind(this);
    document.addEventListener("click", this.handleDocumentClick);
  }

  willDestroy() {
    super.willDestroy();
    document.removeEventListener("click", this.handleDocumentClick);
  }

  handleDocumentClick(event) {
    if (!this.expandedInfo) {
      return;
    }

    const infoPanel = event.target.closest(".info-panel");
    const infoIcon = event.target.closest(".info-icon");

    if (!infoPanel && !infoIcon) {
      this.expandedInfo = null;
    }
  }

  /**
   * Loads the leaderboards for the current period. A response for a period that is no
   * longer selected is discarded.
   */
  @action
  async loadLeaderboard() {
    const period = this.args.period;
    this.isLoading = true;
    try {
      const result = await ajax("/vzekc-verlosung/history/leaderboard.json", {
        data: { period },
      });
      if (period === this.args.period) {
        this.leaderboard = result;
      }
    } finally {
      if (period === this.args.period) {
        this.isLoading = false;
      }
    }
  }

  @action
  toggleInfo(section, event) {
    event.stopPropagation();
    if (this.expandedInfo === section) {
      this.expandedInfo = null;
    } else {
      this.expandedInfo = section;
    }
  }

  /**
   * Opens the entries behind a user's number in a leaderboard
   *
   * @param {string} kind - "lotteries", "tickets", "wins", or "uncollected"
   * @param {Object} entry - Leaderboard entry with user and count
   */
  @action
  showDetails(kind, entry) {
    this.modal.show(LeaderboardDetailsModal, {
      model: {
        kind,
        user: entry.user,
        count: entry.count,
        period: this.args.period,
      },
    });
  }

  formatLuck(luck) {
    if (luck >= 0) {
      return `+${luck}`;
    }
    return `${luck}`;
  }

  <template>
    <div class="lottery-leaderboard" {{didUpdate this.loadLeaderboard @period}}>
      {{#if this.isLoading}}
        <div class="leaderboard-loading">
          {{icon "spinner" class="fa-spin"}}
          {{i18n "loading"}}
        </div>
      {{else if this.leaderboard}}
        <div class="leaderboard-columns">
          {{! Lotteries }}
          <div class="leaderboard-section">
            <h3 class="leaderboard-title">
              {{icon "dice"}}
              {{i18n "vzekc_verlosung.history.leaderboard.lotteries"}}
              <button
                type="button"
                class="info-icon btn-flat"
                {{on "click" (fn this.toggleInfo "lotteries")}}
              >{{icon "circle-info"}}</button>
              {{#if (eq this.expandedInfo "lotteries")}}
                <div class="info-panel">
                  {{i18n "vzekc_verlosung.history.leaderboard.lotteries_info"}}
                </div>
              {{/if}}
            </h3>
            {{#if this.leaderboard.lotteries.length}}
              <ul class="leaderboard-list">
                {{#each this.leaderboard.lotteries as |entry|}}
                  <li class="leaderboard-entry">
                    <button
                      type="button"
                      class="user-info btn-flat show-details"
                      {{on "click" (fn this.showDetails "lotteries" entry)}}
                    >
                      {{avatar entry.user imageSize="small"}}
                      <span class="username">{{entry.user.username}}</span>
                    </button>
                    <span class="count">{{entry.count}}</span>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class="no-data">{{i18n
                  "vzekc_verlosung.history.leaderboard.no_data"
                }}</p>
            {{/if}}
          </div>

          {{! Tickets }}
          <div class="leaderboard-section">
            <h3 class="leaderboard-title">
              {{icon "ticket"}}
              {{i18n "vzekc_verlosung.history.leaderboard.tickets"}}
              <button
                type="button"
                class="info-icon btn-flat"
                {{on "click" (fn this.toggleInfo "tickets")}}
              >{{icon "circle-info"}}</button>
              {{#if (eq this.expandedInfo "tickets")}}
                <div class="info-panel">
                  {{i18n "vzekc_verlosung.history.leaderboard.tickets_info"}}
                </div>
              {{/if}}
            </h3>
            {{#if this.leaderboard.tickets.length}}
              <ul class="leaderboard-list">
                {{#each this.leaderboard.tickets as |entry|}}
                  <li class="leaderboard-entry">
                    <button
                      type="button"
                      class="user-info btn-flat show-details"
                      {{on "click" (fn this.showDetails "tickets" entry)}}
                    >
                      {{avatar entry.user imageSize="small"}}
                      <span class="username">{{entry.user.username}}</span>
                    </button>
                    <span class="count">{{entry.count}}</span>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class="no-data">{{i18n
                  "vzekc_verlosung.history.leaderboard.no_data"
                }}</p>
            {{/if}}
          </div>

          {{! Wins }}
          <div class="leaderboard-section">
            <h3 class="leaderboard-title">
              {{icon "trophy"}}
              {{i18n "vzekc_verlosung.history.leaderboard.wins"}}
              <button
                type="button"
                class="info-icon btn-flat"
                {{on "click" (fn this.toggleInfo "wins")}}
              >{{icon "circle-info"}}</button>
              {{#if (eq this.expandedInfo "wins")}}
                <div class="info-panel">
                  {{i18n "vzekc_verlosung.history.leaderboard.wins_info"}}
                </div>
              {{/if}}
            </h3>
            {{#if this.leaderboard.wins.length}}
              <ul class="leaderboard-list">
                {{#each this.leaderboard.wins as |entry|}}
                  <li class="leaderboard-entry">
                    <button
                      type="button"
                      class="user-info btn-flat show-details"
                      {{on "click" (fn this.showDetails "wins" entry)}}
                    >
                      {{avatar entry.user imageSize="small"}}
                      <span class="username">{{entry.user.username}}</span>
                    </button>
                    <span class="count">{{entry.count}}</span>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class="no-data">{{i18n
                  "vzekc_verlosung.history.leaderboard.no_data"
                }}</p>
            {{/if}}
          </div>

          {{! Luckiest }}
          <div class="leaderboard-section">
            <h3 class="leaderboard-title">
              {{icon "clover"}}
              {{i18n "vzekc_verlosung.history.leaderboard.luckiest"}}
              <button
                type="button"
                class="info-icon btn-flat"
                {{on "click" (fn this.toggleInfo "luckiest")}}
              >{{icon "circle-info"}}</button>
              {{#if (eq this.expandedInfo "luckiest")}}
                <div class="info-panel">
                  {{i18n "vzekc_verlosung.history.leaderboard.luckiest_info"}}
                </div>
              {{/if}}
            </h3>
            {{#if this.leaderboard.luckiest.length}}
              <ul class="leaderboard-list">
                {{#each this.leaderboard.luckiest as |entry|}}
                  <li class="leaderboard-entry">
                    <span class="user-info">
                      {{avatar entry.user imageSize="small"}}
                      <a
                        href="/u/{{entry.user.username}}/verlosungen"
                        class="username"
                      >
                        {{entry.user.username}}
                      </a>
                    </span>
                    <span
                      class="count luck-value luck-positive"
                      title="{{entry.wins}} {{i18n
                        'vzekc_verlosung.history.leaderboard.luck_wins'
                      }} / {{entry.expected}} {{i18n
                        'vzekc_verlosung.history.leaderboard.luck_expected'
                      }}"
                    >
                      {{this.formatLuck entry.luck}}
                    </span>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class="no-data">{{i18n
                  "vzekc_verlosung.history.leaderboard.no_data"
                }}</p>
            {{/if}}
          </div>

          {{! Unluckiest }}
          <div class="leaderboard-section">
            <h3 class="leaderboard-title">
              {{icon "cloud-rain"}}
              {{i18n "vzekc_verlosung.history.leaderboard.unluckiest"}}
              <button
                type="button"
                class="info-icon btn-flat"
                {{on "click" (fn this.toggleInfo "unluckiest")}}
              >{{icon "circle-info"}}</button>
              {{#if (eq this.expandedInfo "unluckiest")}}
                <div class="info-panel">
                  {{i18n "vzekc_verlosung.history.leaderboard.unluckiest_info"}}
                </div>
              {{/if}}
            </h3>
            {{#if this.leaderboard.unluckiest.length}}
              <ul class="leaderboard-list">
                {{#each this.leaderboard.unluckiest as |entry|}}
                  <li class="leaderboard-entry">
                    <span class="user-info">
                      {{avatar entry.user imageSize="small"}}
                      <a
                        href="/u/{{entry.user.username}}/verlosungen"
                        class="username"
                      >
                        {{entry.user.username}}
                      </a>
                    </span>
                    <span
                      class="count luck-value luck-negative"
                      title="{{entry.wins}} {{i18n
                        'vzekc_verlosung.history.leaderboard.luck_wins'
                      }} / {{entry.expected}} {{i18n
                        'vzekc_verlosung.history.leaderboard.luck_expected'
                      }}"
                    >
                      {{this.formatLuck entry.luck}}
                    </span>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class="no-data">{{i18n
                  "vzekc_verlosung.history.leaderboard.no_data"
                }}</p>
            {{/if}}
          </div>

          {{! Uncollected }}
          <div class="leaderboard-section">
            <h3 class="leaderboard-title">
              {{icon "box-open"}}
              {{i18n "vzekc_verlosung.history.leaderboard.uncollected"}}
              <button
                type="button"
                class="info-icon btn-flat"
                {{on "click" (fn this.toggleInfo "uncollected")}}
              >{{icon "circle-info"}}</button>
              {{#if (eq this.expandedInfo "uncollected")}}
                <div class="info-panel">
                  {{i18n
                    "vzekc_verlosung.history.leaderboard.uncollected_info"
                  }}
                </div>
              {{/if}}
            </h3>
            {{#if this.leaderboard.uncollected.length}}
              <ul class="leaderboard-list">
                {{#each this.leaderboard.uncollected as |entry|}}
                  <li class="leaderboard-entry">
                    <button
                      type="button"
                      class="user-info btn-flat show-details"
                      {{on "click" (fn this.showDetails "uncollected" entry)}}
                    >
                      {{avatar entry.user imageSize="small"}}
                      <span class="username">{{entry.user.username}}</span>
                    </button>
                    <span class="count">{{entry.count}}</span>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class="no-data">{{i18n
                  "vzekc_verlosung.history.leaderboard.no_uncollected"
                }}</p>
            {{/if}}
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
