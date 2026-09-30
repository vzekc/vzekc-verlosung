import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";

/**
 * Look-back periods offered on the statistics page, in display order
 *
 * @type {string[]}
 */
export const PERIODS = ["3m", "6m", "1y", "all"];

export default class LotteryHistoryController extends Controller {
  @tracked activeTab = "leaderboard";

  /**
   * Selected look-back period, one of PERIODS
   *
   * @type {string}
   */
  @tracked period = "all";

  queryParams = ["tab", "period"];

  @action
  setActiveTab(tab) {
    this.activeTab = tab;
  }

  /**
   * Selects the look-back period for all statistics
   *
   * @param {string} period - One of PERIODS
   */
  @action
  setPeriod(period) {
    this.period = period;
  }
}
