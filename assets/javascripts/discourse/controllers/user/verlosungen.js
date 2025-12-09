import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";

export default class UserVerlosungenController extends Controller {
  @tracked isLoading = true;
  @tracked stats = null;
  @tracked luck = null;
  @tracked wonPackets = [];
  @tracked lotteriesCreated = [];
  @tracked pickups = [];
  @tracked activeTab = "stats";

  @action
  async loadData() {
    const username = this.model.user.username;

    try {
      const result = await ajax(`/vzekc-verlosung/users/${username}.json`);
      this.stats = result.stats;
      this.luck = result.luck;
      this.wonPackets = result.won_packets;
      this.lotteriesCreated = result.lotteries_created;
      this.pickups = result.pickups;
    } finally {
      this.isLoading = false;
    }
  }

  @action
  switchTab(tab) {
    this.activeTab = tab;
  }
}
