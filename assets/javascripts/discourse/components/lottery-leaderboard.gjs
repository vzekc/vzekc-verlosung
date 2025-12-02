import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { eq } from "truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * Displays leaderboards for lottery creators, ticket buyers, winners, and luck
 *
 * @component LotteryLeaderboard
 */
export default class LotteryLeaderboard extends Component {
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

  async loadLeaderboard() {
    try {
      const result = await ajax("/vzekc-verlosung/history/leaderboard.json");
      this.leaderboard = result;
    } finally {
      this.isLoading = false;
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

  formatLuck(luck) {
    if (luck >= 0) {
      return `+${luck}`;
    }
    return `${luck}`;
  }

  <template>
    <div class="lottery-leaderboard">
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
                    <span class="user-info">
                      {{avatar entry.user imageSize="small"}}
                      <a href="/u/{{entry.user.username}}" class="username">
                        {{entry.user.username}}
                      </a>
                    </span>
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
                    <span class="user-info">
                      {{avatar entry.user imageSize="small"}}
                      <a href="/u/{{entry.user.username}}" class="username">
                        {{entry.user.username}}
                      </a>
                    </span>
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
                    <span class="user-info">
                      {{avatar entry.user imageSize="small"}}
                      <a href="/u/{{entry.user.username}}" class="username">
                        {{entry.user.username}}
                      </a>
                    </span>
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
                      <a href="/u/{{entry.user.username}}" class="username">
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
                      <a href="/u/{{entry.user.username}}" class="username">
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
        </div>
      {{/if}}
    </div>
  </template>
}
