import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";

export default class LotteryHistoryController extends Controller {
  @tracked activeTab = "leaderboard";

  queryParams = ["tab"];

  @action
  setActiveTab(tab) {
    this.activeTab = tab;
  }
}
