import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";

// Points per outcome, matching PickupOffer::BALANCE_POINTS on the server
const POINTS = { passed_on: -1, partial: 0, kept: 1, pending: 1 };

/**
 * Format a number with an explicit sign, e.g. "+2", "−1" or "0"
 *
 * @param {number} value
 * @returns {string}
 */
function signed(value) {
  if (value > 0) {
    return `+${value}`;
  }
  if (value < 0) {
    return `−${Math.abs(value)}`;
  }
  return "0";
}

/**
 * Shows a picker's pickup balance and how each outcome contributes to it,
 * e.g. "Abholsaldo −1: 2× weiterverlost (−2) · 1× noch offen (+1)"
 *
 * @component PickupStats
 * @param {Object} @stats - Pickup statistics from the server: counts for kept, passed_on, partial and pending, and the resulting balance
 */
export default class PickupStats extends Component {
  /**
   * The balance with an explicit sign
   *
   * @returns {string}
   */
  get formattedBalance() {
    return signed(this.args.stats?.balance || 0);
  }

  /**
   * One entry per non-zero outcome, each naming its count and its
   * contribution to the balance
   *
   * @returns {Array<string>}
   */
  get parts() {
    const stats = this.args.stats || {};
    return Object.keys(POINTS)
      .filter((outcome) => stats[outcome] > 0)
      .map((outcome) =>
        i18n(`vzekc_verlosung.donation.pickup_stats.${outcome}`, {
          count: stats[outcome],
          points: signed(stats[outcome] * POINTS[outcome]),
        })
      );
  }

  <template>
    {{#if @stats}}
      <span
        class="pickup-stats"
        title={{i18n "vzekc_verlosung.donation.pickup_stats.title"}}
      >
        <span class="pickup-stats-balance">
          {{i18n
            "vzekc_verlosung.donation.pickup_stats.balance"
            balance=this.formattedBalance
          }}</span>{{#if this.parts.length}}:
          {{#each this.parts as |part index|}}
            {{#if index}}
              ·
            {{/if}}
            <span class="pickup-stats-part">{{part}}</span>
          {{/each}}
        {{else}}
          <span class="pickup-stats-none">–
            {{i18n "vzekc_verlosung.donation.pickup_stats.none"}}</span>
        {{/if}}
      </span>
    {{/if}}
  </template>
}
