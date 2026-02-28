import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";

const CACHE_KEY = "my-lotteries-page-state";

export default class MyLotteriesController extends Controller {
  @service historyStore;
  @service router;

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
   * Refresh the model to reload lotteries after a fulfillment change
   */
  @action
  refreshModel() {
    this.router.refresh();
  }
}
