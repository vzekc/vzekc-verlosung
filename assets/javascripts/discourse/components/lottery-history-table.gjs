import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import formatDate from "discourse/helpers/format-date";
import { i18n } from "discourse-i18n";

/**
 * Displays a sortable table of all lottery packets
 *
 * @component LotteryHistoryTable
 * @param {Array} args.packets - Array of packet objects
 */
export default class LotteryHistoryTable extends Component {
  @tracked sortColumn = "won_at";
  @tracked sortDirection = "desc";

  get sortIcon() {
    return this.sortDirection === "asc" ? "arrow-up" : "arrow-down";
  }

  get isPacketSorted() {
    return this.sortColumn === "packet";
  }

  get isWinnerSorted() {
    return this.sortColumn === "winner";
  }

  get isWonAtSorted() {
    return this.sortColumn === "won_at";
  }

  get isCollectedSorted() {
    return this.sortColumn === "collected";
  }

  get isBerichtDateSorted() {
    return this.sortColumn === "bericht_date";
  }

  get sortedPackets() {
    const packets = [...this.args.packets];

    return packets.sort((a, b) => {
      let aVal, bVal;

      switch (this.sortColumn) {
        case "packet":
          aVal = a.title?.toLowerCase() || "";
          bVal = b.title?.toLowerCase() || "";
          break;
        case "winner":
          aVal = a.winner?.username?.toLowerCase() || "";
          bVal = b.winner?.username?.toLowerCase() || "";
          break;
        case "won_at":
          aVal = a.won_at ? new Date(a.won_at) : new Date(0);
          bVal = b.won_at ? new Date(b.won_at) : new Date(0);
          break;
        case "collected":
          aVal = a.collected_at ? new Date(a.collected_at) : new Date(0);
          bVal = b.collected_at ? new Date(b.collected_at) : new Date(0);
          break;
        case "bericht_date":
          aVal = a.erhaltungsbericht?.created_at
            ? new Date(a.erhaltungsbericht.created_at)
            : new Date(0);
          bVal = b.erhaltungsbericht?.created_at
            ? new Date(b.erhaltungsbericht.created_at)
            : new Date(0);
          break;
        default:
          return 0;
      }

      if (this.sortDirection === "asc") {
        return aVal > bVal ? 1 : aVal < bVal ? -1 : 0;
      } else {
        return aVal < bVal ? 1 : aVal > bVal ? -1 : 0;
      }
    });
  }

  @action
  sortBy(column) {
    if (this.sortColumn === column) {
      this.sortDirection = this.sortDirection === "asc" ? "desc" : "asc";
    } else {
      this.sortColumn = column;
      this.sortDirection = "asc";
    }
  }

  <template>
    {{#if @packets.length}}
      <div class="lottery-history-table-container">
        <table class="lottery-history-table">
          <thead>
            <tr>
              <th
                class="sortable"
                role="button"
                {{on "click" (fn this.sortBy "packet")}}
              >
                {{i18n "vzekc_verlosung.history.table.packet"}}
                {{#if this.isPacketSorted}}
                  {{icon this.sortIcon}}
                {{/if}}
              </th>
              <th
                class="sortable"
                role="button"
                {{on "click" (fn this.sortBy "winner")}}
              >
                {{i18n "vzekc_verlosung.history.table.winner"}}
                {{#if this.isWinnerSorted}}
                  {{icon this.sortIcon}}
                {{/if}}
              </th>
              <th
                class="sortable"
                role="button"
                {{on "click" (fn this.sortBy "won_at")}}
              >
                {{i18n "vzekc_verlosung.history.table.won_at"}}
                {{#if this.isWonAtSorted}}
                  {{icon this.sortIcon}}
                {{/if}}
              </th>
              <th
                class="sortable"
                role="button"
                {{on "click" (fn this.sortBy "collected")}}
              >
                {{i18n "vzekc_verlosung.history.table.collected"}}
                {{#if this.isCollectedSorted}}
                  {{icon this.sortIcon}}
                {{/if}}
              </th>
              <th>{{i18n
                  "vzekc_verlosung.history.table.erhaltungsbericht"
                }}</th>
              <th
                class="sortable"
                role="button"
                {{on "click" (fn this.sortBy "bericht_date")}}
              >
                {{i18n "vzekc_verlosung.history.table.bericht_date"}}
                {{#if this.isBerichtDateSorted}}
                  {{icon this.sortIcon}}
                {{/if}}
              </th>
            </tr>
          </thead>
          <tbody>
            {{#each this.sortedPackets as |packet|}}
              <tr>
                <td class="packet-title-cell">
                  <a href={{packet.packet_url}}>{{packet.title}}</a>
                </td>
                <td class="winner-cell">
                  {{avatar packet.winner imageSize="tiny"}}
                  <a href="/u/{{packet.winner.username}}">
                    {{packet.winner.username}}
                  </a>
                </td>
                <td class="won-date-cell">
                  {{#if packet.won_at}}
                    {{formatDate packet.won_at format="medium"}}
                  {{else}}
                    <span class="no-data">-</span>
                  {{/if}}
                </td>
                <td class="collected-cell">
                  {{#if packet.collected_at}}
                    <span class="status-collected">
                      {{icon "check"}}
                      {{formatDate packet.collected_at format="medium"}}
                    </span>
                  {{else}}
                    <span class="no-data">-</span>
                  {{/if}}
                </td>
                <td class="erhaltungsbericht-cell">
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
                    </span>
                  {{/if}}
                </td>
                <td class="bericht-date-cell">
                  {{#if packet.erhaltungsbericht}}
                    {{formatDate
                      packet.erhaltungsbericht.created_at
                      format="medium"
                    }}
                  {{else}}
                    <span class="no-data">-</span>
                  {{/if}}
                </td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      </div>
    {{else}}
      <div class="no-packets">
        {{i18n "vzekc_verlosung.history.no_packets"}}
      </div>
    {{/if}}
  </template>
}
