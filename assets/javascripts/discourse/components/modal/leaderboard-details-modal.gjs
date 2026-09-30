import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat } from "@ember/helper";
import DModal from "discourse/components/d-modal";
import icon from "discourse/helpers/d-icon";
import formatDate from "discourse/helpers/format-date";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * Lists the entries behind a user's number in a statistics leaderboard: the lotteries
 * they ran, the packets they drew tickets for, the packets they won, or their
 * uncollected wins
 *
 * @component LeaderboardDetailsModal
 * @param {string} model.kind - "lotteries", "tickets", "wins", or "uncollected"
 * @param {Object} model.user - User entry from the leaderboard
 * @param {number} model.count - The number shown in the leaderboard
 * @param {string} model.period - Look-back period ("3m", "6m", "1y" or "all")
 */
export default class LeaderboardDetailsModal extends Component {
  @tracked entries = [];
  @tracked isLoading = true;

  constructor() {
    super(...arguments);
    this.loadEntries();
  }

  /**
   * Modal title naming the leaderboard, the user, and the number
   *
   * @returns {string}
   */
  get title() {
    return i18n(
      `vzekc_verlosung.history.leaderboard.details.${this.args.model.kind}`,
      {
        username: this.args.model.user.username,
        number: this.args.model.count,
      }
    );
  }

  /**
   * Loads the entries for the user, leaderboard, and period
   */
  async loadEntries() {
    const { kind, user, period } = this.args.model;
    try {
      const result = await ajax(
        `/vzekc-verlosung/history/leaderboard/${kind}/${encodeURIComponent(
          user.username
        )}.json`,
        { data: { period } }
      );
      this.entries = result.entries;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  <template>
    <DModal
      @title={{this.title}}
      @closeModal={{@closeModal}}
      class="leaderboard-details-modal"
    >
      <:body>
        {{#if this.isLoading}}
          <div class="leaderboard-loading">
            {{icon "spinner" class="fa-spin"}}
            {{i18n "loading"}}
          </div>
        {{else if this.entries.length}}
          <table class="leaderboard-details">
            <tbody>
              {{#each this.entries as |entry|}}
                <tr>
                  <td class="date">{{formatDate
                      entry.date
                      format="medium"
                    }}</td>
                  <td class="title">
                    <a href={{entry.url}}>{{entry.title}}</a>
                    {{#if entry.lottery}}
                      <a href={{entry.lottery.url}} class="lottery">
                        {{entry.lottery.title}}
                      </a>
                    {{/if}}
                  </td>
                  <td class="detail">
                    {{#if (eq @model.kind "lotteries")}}
                      {{i18n
                        "vzekc_verlosung.history.leaderboard.details.packets"
                        count=entry.packets
                      }}<br />
                      {{i18n
                        "vzekc_verlosung.history.leaderboard.details.participants"
                        count=entry.participants
                      }}
                    {{else if (eq @model.kind "tickets")}}
                      {{i18n
                        "vzekc_verlosung.history.leaderboard.details.participants"
                        count=entry.participants
                      }}
                      {{#if entry.won}}
                        <span class="won">{{icon "trophy"}}
                          {{i18n "vzekc_verlosung.status.won"}}</span>
                      {{/if}}
                    {{else if (eq @model.kind "wins")}}
                      {{#if entry.participants}}
                        {{i18n
                          "vzekc_verlosung.history.leaderboard.details.participants"
                          count=entry.participants
                        }}<br />
                      {{/if}}
                      {{i18n (concat "vzekc_verlosung.status." entry.state)}}
                    {{else}}
                      <span class="waiting">{{i18n
                          "vzekc_verlosung.history.leaderboard.details.days_waiting"
                          count=entry.days_waiting
                        }}</span><br />
                      {{i18n
                        "vzekc_verlosung.history.leaderboard.details.owner"
                        username=entry.owner
                      }}
                    {{/if}}
                  </td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        {{else}}
          <p class="no-data">{{i18n
              "vzekc_verlosung.history.leaderboard.no_data"
            }}</p>
        {{/if}}
      </:body>
    </DModal>
  </template>
}
