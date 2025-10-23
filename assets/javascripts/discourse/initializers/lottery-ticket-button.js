import { apiInitializer } from "discourse/lib/api";
import LotteryTicketButton from "../components/lottery-ticket-button";
import LotteryTicketCount from "../components/lottery-ticket-count";

export default apiInitializer("1.14.0", (api) => {
  api.registerValueTransformer("post-menu-buttons", ({ value: dag }) => {
    dag.add("lottery-ticket", LotteryTicketButton, { before: "share" });
    dag.add("lottery-ticket-count", LotteryTicketCount, { after: "lottery-ticket" });
  });
});
