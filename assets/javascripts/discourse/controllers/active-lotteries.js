import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";

const CACHE_KEY = "lotteries-page-state";

export default class ActiveLotteriesController extends Controller {
  @service historyStore;

  @tracked activeTab = "active";
  @tracked finishedLotteries = null;
  @tracked loadingFinished = false;
  @tracked expandedIds = [];

  queryParams = ["tab"];

  /**
   * Initialize controller state from historyStore cache
   */
  init() {
    super.init(...arguments);
    this.restoreState();
  }

  /**
   * Restore state from historyStore cache
   */
  restoreState() {
    const cached = this.historyStore.get(CACHE_KEY);
    if (cached) {
      this.expandedIds = cached.expandedIds || [];
      if (cached.finishedLotteries) {
        this.finishedLotteries = cached.finishedLotteries;
      }
    }
  }

  /**
   * Save current state to historyStore
   */
  saveState() {
    this.historyStore.set(CACHE_KEY, {
      expandedIds: this.expandedIds,
      finishedLotteries: this.finishedLotteries,
      scrollPosition: window.scrollY,
    });
  }

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
   * Toggle expanded state for a lottery
   *
   * @param {Number} lotteryId - Lottery ID to toggle
   */
  @action
  toggleExpanded(lotteryId) {
    if (this.expandedIds.includes(lotteryId)) {
      this.expandedIds = this.expandedIds.filter((id) => id !== lotteryId);
    } else {
      this.expandedIds = [...this.expandedIds, lotteryId];
    }
    this.saveState();
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
      this.saveState();
    } catch {
      this.finishedLotteries = [];
    } finally {
      this.loadingFinished = false;
    }
  }

  /**
   * Get cached scroll position for restoration
   *
   * @returns {number} Cached scroll position or 0
   */
  getScrollPosition() {
    const cached = this.historyStore.get(CACHE_KEY);
    return cached?.scrollPosition || 0;
  }
}
