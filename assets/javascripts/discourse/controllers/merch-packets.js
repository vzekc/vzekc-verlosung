import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";

export default class MerchPacketsController extends Controller {
  @service router;

  /**
   * Packet ID to open shipping modal for (from query param)
   *
   * @type {string|null}
   */
  @tracked ship = null;

  queryParams = ["ship"];

  /**
   * Refresh the model to reload merch packets after a change
   */
  @action
  refreshModel() {
    this.router.refresh();
  }
}
