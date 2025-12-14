import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";

export default class UserVerlosungenController extends Controller {
  @tracked tab = "stats";
  queryParams = ["tab"];

  @action
  updateTab(newTab) {
    this.tab = newTab;
  }
}
