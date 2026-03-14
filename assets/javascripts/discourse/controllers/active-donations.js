import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";

export default class ActiveDonationsController extends Controller {
  @service router;

  /**
   * Refresh the model to reload donations after a change
   */
  @action
  refreshModel() {
    this.router.refresh();
  }
}
