import { apiInitializer } from "discourse/lib/api";

/**
 * Hides lottery draft topics from topic lists for users who don't own them
 */
export default apiInitializer((api) => {
  const currentUser = api.getCurrentUser();

  // Hide draft topics from topic lists
  api.modifyClass("model:topic", {
    pluginId: "vzekc-verlosung",

    /**
     * Override isVisible to hide lottery drafts from non-owners
     *
     * @returns {Boolean} whether the topic should be visible in lists
     */
    get isVisible() {
      const isDraft = this.lottery_state === "draft";

      if (!isDraft) {
        return this._super(...arguments);
      }

      // If it's a draft, only show to owner
      if (!currentUser) {
        return false;
      }

      if (this.user_id === currentUser.id) {
        return this._super(...arguments);
      }

      return false;
    },
  });
});
