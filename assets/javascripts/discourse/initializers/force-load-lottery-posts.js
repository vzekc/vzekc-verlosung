import { apiInitializer } from "discourse/lib/api";

/**
 * Force load all posts in lottery topics to prevent gaps/hidden posts
 *
 * Lottery topics need all packet posts visible, so we automatically
 * load the full post stream instead of showing "Load more" gaps.
 * Also cleans up problematic query parameters that might hide posts.
 */
export default apiInitializer((api) => {
  // Hook into topic route to load all posts for lottery topics
  api.modifyClass("route:topic", {
    pluginId: "vzekc-verlosung",

    setupController(controller, model) {
      this._super(controller, model);

      // Check if this is a lottery topic
      if (model && model.lottery_state) {
        // Clean up problematic query parameters that hide posts
        // These can appear after publishing and break the post stream
        const url = new URL(window.location.href);
        const hasNullParams =
          url.searchParams.get("replies_to_post_number") === "null" ||
          url.searchParams.get("filter") === "null" ||
          url.searchParams.get("username_filters") === "null";

        if (hasNullParams) {
          // eslint-disable-next-line no-console
          console.log(
            "[vzekc-verlosung] Removing problematic query parameters"
          );
          // Redirect to clean URL without query parameters
          window.location.href = window.location.pathname;
          return;
        }

        const postStream = controller.get("model.postStream");

        // Schedule loading all posts after initial render
        if (postStream && postStream.get("hasGaps")) {
          // eslint-disable-next-line no-console
          console.log("[vzekc-verlosung] Loading all posts for lottery topic");

          // Use a small delay to let the page render first
          setTimeout(() => {
            postStream.loadAllPosts();
          }, 100);
        }
      }
    },
  });
});
