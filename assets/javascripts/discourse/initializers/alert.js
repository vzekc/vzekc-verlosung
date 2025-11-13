import { apiInitializer } from "discourse/lib/api";
import NeueVerlosungButton from "../components/neue-verlosung-button";

/**
 * Initializer to add the "Neue Verlosung" button to category pages
 */
export default apiInitializer((api) => {
  // Add button to category page using renderInOutlet
  api.renderInOutlet("category-navigation", NeueVerlosungButton);
});
