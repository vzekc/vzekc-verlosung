import { schedule } from "@ember/runloop";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseRoute from "discourse/routes/discourse";

export default class MyLotteries extends DiscourseRoute {
  beforeModel() {
    if (!this.currentUser) {
      this.router.replaceWith("login");
      return;
    }
    if (!this.siteSettings.vzekc_verlosung_enabled) {
      this.router.replaceWith("discovery.latest");
    }
  }

  model() {
    return ajax("/vzekc-verlosung/my-lotteries/active.json", {
      type: "GET",
    }).catch(popupAjaxError);
  }

  /**
   * Set active lotteries on controller, restore state and scroll position
   */
  setupController(controller, model) {
    super.setupController(controller, model);
    controller.setActiveLotteries(model.lotteries);
    controller.restoreState();

    schedule("afterRender", () => {
      const scrollPosition = controller.getScrollPosition();
      if (scrollPosition > 0) {
        window.scrollTo(0, scrollPosition);
      }
    });
  }

  /**
   * Save scroll position before leaving the route
   */
  deactivate() {
    super.deactivate(...arguments);
    this.controller?.saveScrollPosition();
  }
}
