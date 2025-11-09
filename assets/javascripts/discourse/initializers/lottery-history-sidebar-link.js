import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

export default apiInitializer("1.34.0", (api) => {
  api.addCommunitySectionLink({
    name: "lottery_history",
    route: "lotteryHistory",
    title: i18n("vzekc_verlosung.history.sidebar_link_title"),
    text: i18n("vzekc_verlosung.history.sidebar_link_text"),
    icon: "list",
  });
});
