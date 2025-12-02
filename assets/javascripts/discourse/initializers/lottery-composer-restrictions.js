import { withPluginApi } from "discourse/lib/plugin-api";
import { EDIT } from "discourse/models/composer";

/**
 * Hide the category chooser when editing a lottery topic's first post.
 * This prevents users from attempting to change the category, which is
 * blocked by server-side validation.
 */
export default {
  name: "lottery-composer-restrictions",

  initialize() {
    withPluginApi((api) => {
      api.modifyClass("model:composer", {
        pluginId: "vzekc-verlosung-composer",

        get showCategoryChooser() {
          // Check if we're editing a lottery topic
          if (this.action === EDIT && this.topic?.lottery_state) {
            // Hide category chooser for lottery topics
            return false;
          }

          // Fall back to default behavior
          const isPrivateMessage = this.privateMessage;
          const hasOptions = this.archetype?.hasOptions;
          const manyCategories = this.site?.categories?.length > 1;
          return !isPrivateMessage && (hasOptions || manyCategories);
        },
      });
    });
  },
};
