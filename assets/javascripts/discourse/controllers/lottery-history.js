import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";

export default class LotteryHistoryController extends Controller {
  queryParams = ["search", "sort"];

  @tracked search = null;
  @tracked sort = "date_desc";

  sortOptions = [
    { value: "date_desc", label: "vzekc_verlosung.history.sort.date_desc" },
    { value: "date_asc", label: "vzekc_verlosung.history.sort.date_asc" },
    { value: "lottery_asc", label: "vzekc_verlosung.history.sort.lottery_asc" },
    { value: "lottery_desc", label: "vzekc_verlosung.history.sort.lottery_desc" },
  ];

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
