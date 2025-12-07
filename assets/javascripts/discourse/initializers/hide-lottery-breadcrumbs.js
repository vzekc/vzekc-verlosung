import { withPluginApi } from "discourse/lib/plugin-api";

/**
 * Hide the category breadcrumb navigation on lottery-related category pages.
 * These categories have restricted access and users should use dedicated pages.
 */
export default {
  name: "hide-lottery-breadcrumbs",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");

    withPluginApi((api) => {
      api.modifyClass("component:bread-crumbs", {
        pluginId: "vzekc-verlosung-breadcrumbs",

        get hidden() {
          // Check parent's hidden logic first (e.g., mobile view)
          if (this._super?.(...arguments)) {
            return true;
          }

          // Get hidden category IDs from site settings
          const hiddenCategoryIds = [
            parseInt(siteSettings.vzekc_verlosung_category_id, 10),
            parseInt(
              siteSettings.vzekc_verlosung_erhaltungsberichte_category_id,
              10
            ),
            parseInt(siteSettings.vzekc_verlosung_donation_category_id, 10),
          ].filter((id) => id > 0);

          // Hide breadcrumb for lottery-related categories
          if (this.category && hiddenCategoryIds.includes(this.category.id)) {
            return true;
          }

          return false;
        },
      });
    });
  },
};
