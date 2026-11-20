import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";

const OUTCOMES = ["kept", "passed_on", "partial", "pending"];

/**
 * Shows a picker's pickup balance and the outcomes it is made of
 *
 * @component PickupStats
 * @param {Object} @stats - Pickup statistics from the server: counts for kept, passed_on, partial and pending, and the resulting balance
 */
export default class PickupStats extends Component {
  /**
   * The balance with an explicit sign, e.g. "+2", "−1" or "0"
   *
   * @returns {string}
   */
  get formattedBalance() {
    const balance = this.args.stats?.balance || 0;
    if (balance > 0) {
      return `+${balance}`;
    }
    if (balance < 0) {
      return `−${Math.abs(balance)}`;
    }
    return "0";
  }

  /**
   * Localized description of each non-zero outcome, e.g. "1 behalten"
   *
   * @returns {string}
   */
  get breakdown() {
    const stats = this.args.stats || {};
    const parts = OUTCOMES.filter((outcome) => stats[outcome] > 0).map(
      (outcome) =>
        i18n(`vzekc_verlosung.donation.pickup_stats.${outcome}`, {
          count: stats[outcome],
        })
    );
    return parts.length > 0
      ? parts.join(" · ")
      : i18n("vzekc_verlosung.donation.pickup_stats.none");
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
          }}
        </span>
        <span class="pickup-stats-breakdown">{{this.breakdown}}</span>
      </span>
    {{/if}}
  </template>
}
