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
 * Avatar badge with a picker's pickup balance. Its tooltip lists how each
 * outcome contributes, e.g. "2× weiterverlost (−2)", followed by the rule.
 * Pickers without pickups in the balance window get no badge.
 *
 * @component PickupStats
 * @param {Object} @stats - Pickup statistics from the server: counts for kept, passed_on, partial and pending, and the resulting balance
 */
export default class PickupStats extends Component {
  /**
   * Outcomes with a non-zero count
   *
   * @returns {Array<string>}
   */
  get outcomes() {
    const stats = this.args.stats || {};
    return Object.keys(POINTS).filter((outcome) => stats[outcome] > 0);
  }

  /**
   * The balance with an explicit sign
   *
   * @returns {string}
   */
  get formattedBalance() {
    return signed(this.args.stats?.balance || 0);
  }

  /**
   * Tooltip: the balance, one line per outcome with its contribution, and
   * the rule behind the points
   *
   * @returns {string}
   */
  get tooltip() {
    const stats = this.args.stats;
    const lines = this.outcomes.map((outcome) =>
      i18n(`vzekc_verlosung.donation.pickup_stats.${outcome}`, {
        count: stats[outcome],
        points: signed(stats[outcome] * POINTS[outcome]),
      })
    );
    return [
      i18n("vzekc_verlosung.donation.pickup_stats.balance", {
        balance: this.formattedBalance,
      }),
      ...lines,
      "",
      i18n("vzekc_verlosung.donation.pickup_stats.rule"),
    ].join("\n");
  }

  <template>
    {{#if this.outcomes.length}}
      <span class="pickup-balance-badge" title={{this.tooltip}}>
        {{this.formattedBalance}}
      </span>
    {{/if}}
  </template>
}
