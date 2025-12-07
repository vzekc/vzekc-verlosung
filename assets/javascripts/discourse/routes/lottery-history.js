import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseRoute from "discourse/routes/discourse";

export default class LotteryHistory extends DiscourseRoute {
  queryParams = {
    search: { refreshModel: true },
    sort: { refreshModel: true },
    expanded: { refreshModel: false },
    tab: { refreshModel: false },
  };

  model(params) {
    const queryParams = {};

    if (params.search) {
      queryParams.search = params.search;
    }
    if (params.sort) {
      queryParams.sort = params.sort;
    }

    return ajax("/vzekc-verlosung/history.json", {
      type: "GET",
      data: queryParams,
    }).catch(popupAjaxError);
  }
}
