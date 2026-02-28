import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

const CACHE_KEY = "my-lotteries-page-state";

export default class MyLotteriesController extends Controller {
  @service historyStore;

  @tracked lotteries = [];

  /**
   * Initialize lotteries from route model
   *
   * @param {Array} lotteries
   */
  setLotteries(lotteries) {
    this.lotteries = lotteries;
  }

  /**
   * Save scroll position to historyStore
   */
  saveScrollPosition() {
    this.historyStore.set(CACHE_KEY, {
      scrollPosition: window.scrollY,
    });
  }

  /**
   * Get cached scroll position for restoration
   *
   * @returns {number}
   */
  getScrollPosition() {
    return this.historyStore.get(CACHE_KEY)?.scrollPosition || 0;
  }

  /**
   * Re-fetch lotteries without triggering a route transition
   */
  @action
  async refreshModel() {
    try {
      const result = await ajax("/vzekc-verlosung/my-lotteries.json", {
        type: "GET",
      });
      this.lotteries = result.lotteries;
    } catch (error) {
      popupAjaxError(error);
    }
  }
}
