import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseRoute from "discourse/routes/discourse";

export default class MerchPackets extends DiscourseRoute {
  model() {
    return ajax("/vzekc-verlosung/merch-packets.json", {
      type: "GET",
    }).catch(popupAjaxError);
  }
}
