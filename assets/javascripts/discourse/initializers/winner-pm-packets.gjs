import { apiInitializer } from "discourse/lib/api";
import WinnerPmPackets from "../components/winner-pm-packets";

export default apiInitializer((api) => {
  api.renderInOutlet("topic-map-expanded-after", WinnerPmPackets);
});
