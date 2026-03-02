import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

const CACHE_KEY = "my-lotteries-page-state";

export default class MyLotteriesController extends Controller {
  @service historyStore;

  @tracked activeTab = "active";
  @tracked activeLotteries = null;
  @tracked lotteries = [];
  @tracked loadingFinished = false;

  queryParams = ["tab"];

  /**
   * Initialize active lotteries from route model
   *
   * @param {Array} lotteries
   */
  setActiveLotteries(lotteries) {
    this.activeLotteries = lotteries;
  }

  /**
   * Initialize finished lotteries from data
   *
   * @param {Array} lotteries
   */
  setLotteries(lotteries) {
    this.lotteries = lotteries;
  }

  /**
   * Restore cached state (tab, scroll, finished data)
   */
  restoreState() {
    const cached = this.historyStore.get(CACHE_KEY);
    if (cached) {
      if (cached.activeTab) {
        this.activeTab = cached.activeTab;
      }
      if (cached.lotteries) {
        this.lotteries = cached.lotteries;
      }
    }
  }

  /**
   * Save scroll position and tab state to historyStore
   */
  saveScrollPosition() {
    this.historyStore.set(CACHE_KEY, {
      scrollPosition: window.scrollY,
      activeTab: this.activeTab,
      lotteries: this.lotteries,
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
   * Switch to a different tab
   *
   * @param {string} tab - Tab identifier ("active" or "finished")
   * @param {Event} event - Click event
   */
  @action
  setActiveTab(tab, event) {
    event?.preventDefault();
    this.activeTab = tab;

    if (tab === "finished" && this.lotteries.length === 0) {
      this.loadFinishedLotteries();
    }
  }

  /**
   * Load finished lotteries from the API
   */
  async loadFinishedLotteries() {
    this.loadingFinished = true;

    try {
      const result = await ajax("/vzekc-verlosung/my-lotteries.json", {
        type: "GET",
      });
      this.lotteries = result.lotteries;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loadingFinished = false;
    }
  }

  /**
   * Re-fetch active lotteries without triggering a route transition
   */
  @action
  async refreshActive() {
    try {
      const result = await ajax("/vzekc-verlosung/my-lotteries/active.json", {
        type: "GET",
      });
      this.activeLotteries = result.lotteries;
    } catch (error) {
      popupAjaxError(error);
    }
  }

  /**
   * Re-fetch finished lotteries without triggering a route transition
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
