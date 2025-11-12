import { apiInitializer } from "discourse/lib/api";
import NeueSpendeButton from "../components/neue-spende-button";

/**
 * Initializer to add the "Neue Spende" button to donation category pages
 */
export default apiInitializer((api) => {
  // Add button to category page using renderInOutlet
  api.renderInOutlet("category-navigation", NeueSpendeButton);
});
