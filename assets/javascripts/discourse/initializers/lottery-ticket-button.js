import { apiInitializer } from "discourse/lib/api";
import LotteryTicketButton from "../components/lottery-ticket-button";

export default apiInitializer("1.14.0", (api) => {
  console.log("Lottery ticket button initializer running");

  api.registerValueTransformer("post-menu-buttons", ({ value: dag }) => {
    console.log("Registering lottery ticket button in DAG");
    dag.add("lottery-ticket", LotteryTicketButton, { before: "share" });
  });

  console.log("Lottery ticket button transformer registered");
});
