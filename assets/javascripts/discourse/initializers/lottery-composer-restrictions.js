import { withPluginApi } from "discourse/lib/plugin-api";
import { EDIT } from "discourse/models/composer";

/**
 * Lottery composer restrictions:
 * 1. Hide category chooser when editing lottery topics
 * 2. Hide lottery category from category selector (users must use /new-lottery)
 */
export default {
  name: "lottery-composer-restrictions",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");

    withPluginApi((api) => {
      // Hide category chooser when editing lottery topics
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

      // Hide all lottery-related categories from category chooser
      // Users must use dedicated pages (/new-lottery, donation widget, etc.)
      const hiddenCategoryIds = [
        parseInt(siteSettings.vzekc_verlosung_category_id, 10),
        parseInt(
          siteSettings.vzekc_verlosung_erhaltungsberichte_category_id,
          10
        ),
        parseInt(siteSettings.vzekc_verlosung_donation_category_id, 10),
      ].filter((id) => id > 0);

      if (hiddenCategoryIds.length > 0) {
        api
          .modifySelectKit("category-chooser")
          .replaceContent((component, categories) => {
            return categories.filter(
              (category) => !hiddenCategoryIds.includes(category.id)
            );
          });
      }
    });
  },
};
