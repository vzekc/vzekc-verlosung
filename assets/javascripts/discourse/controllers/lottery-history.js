import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";

export default class LotteryHistoryController extends Controller {
  @tracked search = null;
  @tracked sort = "date_desc";
  @tracked activeTab = "leaderboard";

  queryParams = ["search", "sort", "tab"];

  sortOptions = [
    { value: "date_desc", label: "vzekc_verlosung.history.sort.date_desc" },
    { value: "date_asc", label: "vzekc_verlosung.history.sort.date_asc" },
    { value: "lottery_asc", label: "vzekc_verlosung.history.sort.lottery_asc" },
    {
      value: "lottery_desc",
      label: "vzekc_verlosung.history.sort.lottery_desc",
    },
  ];

  @action
  setActiveTab(tab) {
    this.activeTab = tab;
  }

  @action
  updateSearch(value) {
    this.search = value || null;
  }

  @action
  updateSort(value) {
    this.sort = value;
  }

  @action
  clearFilters() {
    this.search = null;
    this.sort = "date_desc";
  }
}
