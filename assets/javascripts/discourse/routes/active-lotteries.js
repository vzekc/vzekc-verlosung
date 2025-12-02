import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseRoute from "discourse/routes/discourse";

export default class ActiveLotteries extends DiscourseRoute {
  model() {
    return ajax("/vzekc-verlosung/active.json", {
      type: "GET",
    }).catch(popupAjaxError);
  }
}
