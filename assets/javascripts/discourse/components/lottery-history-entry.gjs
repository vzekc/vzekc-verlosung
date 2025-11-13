import Component from "@glimmer/component";
import { htmlSafe } from "@ember/template";
import avatar from "discourse/helpers/avatar";
import { categoryBadgeHTML } from "discourse/helpers/category-link";
import icon from "discourse/helpers/d-icon";
import formatDate from "discourse/helpers/format-date";
import { i18n } from "discourse-i18n";

/**
 * Displays a single lottery history entry with full packet details
 *
 * @component LotteryHistoryEntry
 * @param {Object} args.lottery - Lottery object with packets and winners
 */
export default class LotteryHistoryEntry extends Component {
  get hasWinners() {
    return this.args.lottery.packets.some((p) => p.winner);
  }

  get collectedCount() {
    return this.args.lottery.packets.filter((p) => p.collected_at).length;
  }

  get erhaltungsberichtCount() {
    return this.args.lottery.packets.filter((p) => p.erhaltungsbericht).length;
  }

  <template>
    <div class="lottery-history-entry">
      {{! Header }}
      <div class="lottery-history-entry-header">
        <h3 class="lottery-history-entry-title">
          <a href={{@lottery.url}}>{{@lottery.title}}</a>
        </h3>
        <div class="lottery-history-entry-meta">
          {{htmlSafe (categoryBadgeHTML @lottery.category)}}
          <span class="lottery-history-entry-creator">
            {{avatar @lottery.creator imageSize="tiny"}}
            <a href="/u/{{@lottery.creator.username}}">
              {{@lottery.creator.username}}
            </a>
          </span>
        </div>
      </div>

      {{! Dates }}
      <div class="lottery-history-entry-dates">
        <div class="lottery-history-date">
          {{icon "calendar-plus"}}
          <span class="date-label">
            {{i18n "vzekc_verlosung.history.created"}}:</span>
          <span class="date-value">
            {{formatDate @lottery.created_at format="medium"}}
          </span>
        </div>
        {{#if @lottery.lottery_ends_at}}
          <div class="lottery-history-date">
            {{icon "calendar-check"}}
            <span class="date-label">
              {{i18n "vzekc_verlosung.history.ended"}}:</span>
            <span class="date-value">
              {{formatDate @lottery.lottery_ends_at format="medium"}}
            </span>
          </div>
        {{/if}}
        {{#if @lottery.lottery_drawn_at}}
          <div class="lottery-history-date">
            {{icon "dice"}}
            <span class="date-label">
              {{i18n "vzekc_verlosung.history.drawn"}}:</span>
            <span class="date-value">
              {{formatDate @lottery.lottery_drawn_at format="medium"}}
            </span>
          </div>
        {{/if}}
      </div>

      {{! Summary Stats }}
      <div class="lottery-history-entry-stats">
        <div class="stat-item">
          {{icon "users"}}
          <span>{{@lottery.participant_count}}
            {{i18n "vzekc_verlosung.history.participants"}}</span>
        </div>
        <div class="stat-item">
          {{icon "box"}}
          <span>{{@lottery.packets.length}}
            {{i18n "vzekc_verlosung.history.packets"}}</span>
        </div>
        <div class="stat-item">
          {{icon "check-circle"}}
          <span>{{this.collectedCount}}
            {{i18n "vzekc_verlosung.history.collected"}}</span>
        </div>
        <div class="stat-item">
          {{icon "file-alt"}}
          <span>{{this.erhaltungsberichtCount}}
            {{i18n "vzekc_verlosung.history.erhaltungsberichte"}}</span>
        </div>
      </div>

      {{! Packets Table }}
      <div class="lottery-history-entry-packets">
        <h4 class="packets-table-title">
          {{i18n "vzekc_verlosung.history.packets_and_winners"}}
        </h4>
        <table class="lottery-history-packets-table">
          <thead>
            <tr>
              <th>{{i18n "vzekc_verlosung.history.table.packet"}}</th>
              <th>{{i18n "vzekc_verlosung.history.table.winner"}}</th>
              <th>{{i18n "vzekc_verlosung.history.table.collected"}}</th>
              <th>{{i18n
                  "vzekc_verlosung.history.table.erhaltungsbericht"
                }}</th>
            </tr>
          </thead>
          <tbody>
            {{#each @lottery.packets as |packet|}}
              <tr class="lottery-history-packet-row">
                <td class="packet-title">
                  <a href="{{@lottery.url}}/{{packet.post_number}}">
                    {{packet.title}}
                  </a>
                </td>
                <td class="packet-winner">
                  {{#if packet.winner}}
                    {{avatar packet.winner imageSize="tiny"}}
                    <a href="/u/{{packet.winner.username}}">
                      {{packet.winner.username}}
                    </a>
                  {{else}}
                    <span class="no-winner">
                      {{i18n "vzekc_verlosung.history.no_winner"}}
                    </span>
                  {{/if}}
                </td>
                <td class="packet-collected">
                  {{#if packet.collected_at}}
                    <span class="status-collected">
                      {{icon "check"}}
                      {{formatDate packet.collected_at format="tiny"}}
                    </span>
                  {{else}}
                    <span class="status-not-collected">
                      {{icon "times"}}
                      {{i18n "vzekc_verlosung.history.not_collected"}}
                    </span>
                  {{/if}}
                </td>
                <td class="packet-erhaltungsbericht">
                  {{#if packet.erhaltungsbericht}}
                    <a
                      href={{packet.erhaltungsbericht.url}}
                      class="erhaltungsbericht-link"
                    >
                      {{icon "file-alt"}}
                      {{i18n "vzekc_verlosung.history.view_report"}}
                    </a>
                  {{else}}
                    <span class="status-no-report">
                      {{icon "minus"}}
                      {{i18n "vzekc_verlosung.history.no_report"}}
                    </span>
                  {{/if}}
                </td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      </div>
    </div>
  </template>
}
