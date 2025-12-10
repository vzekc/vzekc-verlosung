import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";

export default class UserVerlosungenController extends Controller {
  queryParams = ["tab"];

  @tracked tab = "stats";

  @action
  updateTab(newTab) {
    this.tab = newTab;
  }
}
