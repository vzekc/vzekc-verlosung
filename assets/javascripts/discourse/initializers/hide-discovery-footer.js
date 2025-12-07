import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

/**
 * Hide the footer message ("start a new conversation" link) on lottery-related
 * category pages. Users must use dedicated pages (/new-lottery, donation widget, etc.)
 */
export default {
  name: "hide-discovery-footer-message",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");

    withPluginApi((api) => {
      api.modifyClass("component:discovery/topics", {
        pluginId: "vzekc-verlosung-footer",

        get footerMessage() {
          // Get hidden category IDs from site settings
          const hiddenCategoryIds = [
            parseInt(siteSettings.vzekc_verlosung_category_id, 10),
            parseInt(
              siteSettings.vzekc_verlosung_erhaltungsberichte_category_id,
              10
            ),
            parseInt(siteSettings.vzekc_verlosung_donation_category_id, 10),
          ].filter((id) => id > 0);

          // Hide footer message for lottery-related categories
          const { category, tag } = this.args;
          if (category && hiddenCategoryIds.includes(category.id)) {
            return null;
          }

          // Replicate original footerMessage logic since _super doesn't work with Glimmer getters
          const topicsLength = this.args.model.get("topics.length");
          if (!this.allLoaded) {
            return;
          }

          const filterSegments = (this.args.model.get("filter") || "").split(
            "/"
          );
          const lastFilterSegment = filterSegments.at(-1);
          const newOrUnreadFilter =
            lastFilterSegment === "new" || lastFilterSegment === "unread";

          if (category) {
            if (topicsLength === 0 && newOrUnreadFilter) {
              return;
            }
            return i18n("topics.bottom.category", { category: category.name });
          } else if (tag) {
            if (topicsLength === 0 && newOrUnreadFilter) {
              return;
            }
            return i18n("topics.bottom.tag", { tag: tag.id });
          } else {
            if (topicsLength === 0) {
              if (newOrUnreadFilter) {
                return;
              }
              return i18n(`topics.none.${lastFilterSegment}`, {
                category: filterSegments[1],
              });
            } else {
              return i18n(`topics.bottom.${lastFilterSegment}`, {
                category: filterSegments[1],
              });
            }
          }
        },
      });
    });
  },
};
