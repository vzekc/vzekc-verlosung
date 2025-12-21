import { schedule } from "@ember/runloop";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseRoute from "discourse/routes/discourse";

export default class ActiveLotteries extends DiscourseRoute {
  model() {
    return ajax("/vzekc-verlosung/active.json", {
      type: "GET",
    }).catch(popupAjaxError);
  }

  /**
   * Restore scroll position after render
   *
   * @param {Controller} controller - The route controller
   */
  setupController(controller, model) {
    super.setupController(controller, model);

    // Restore scroll position after render
    schedule("afterRender", () => {
      const scrollPosition = controller.getScrollPosition();
      if (scrollPosition > 0) {
        window.scrollTo(0, scrollPosition);
      }
    });
  }

  /**
   * Save state before leaving the route
   */
  deactivate() {
    super.deactivate(...arguments);
    this.controller?.saveState();
  }
}
