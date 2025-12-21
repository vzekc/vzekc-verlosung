import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";

export default class ActiveLotteriesController extends Controller {
  @tracked activeTab = "active";
  @tracked finishedLotteries = null;
  @tracked loadingFinished = false;

  queryParams = ["tab"];

  /**
   * Switch to a different tab
   *
   * @param {String} tab - Tab identifier ("active" or "finished")
   * @param {Event} event - Click event
   */
  @action
  setActiveTab(tab, event) {
    event?.preventDefault();
    this.activeTab = tab;

    // Load finished lotteries on first switch to that tab
    if (tab === "finished" && this.finishedLotteries === null) {
      this.loadFinishedLotteries();
    }
  }

  /**
   * Load finished lotteries from the API
   */
  async loadFinishedLotteries() {
    this.loadingFinished = true;

    try {
      const result = await ajax("/vzekc-verlosung/history/lotteries.json", {
        type: "GET",
        data: { per_page: 50 },
      });
      this.finishedLotteries = result.lotteries || [];
    } catch {
      this.finishedLotteries = [];
    } finally {
      this.loadingFinished = false;
    }
  }
}
