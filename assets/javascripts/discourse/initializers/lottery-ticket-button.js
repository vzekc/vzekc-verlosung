import { apiInitializer } from "discourse/lib/api";
import LotteryWidget from "../components/lottery-widget";

export default apiInitializer((api) => {
  api.registerValueTransformer("post-menu-buttons", ({ value: dag }) => {
    dag.add("lottery-widget", LotteryWidget, { before: "share" });
  });
});
