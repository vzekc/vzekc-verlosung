import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

export default {
  name: "verlosung-sidebar-section",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    const site = container.lookup("service:site");

    if (!siteSettings.vzekc_verlosung_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.addSidebarSection(
        (BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
          const ActiveLotteriesLink = class extends BaseCustomSidebarSectionLink {
            get name() {
              return "active-lotteries";
            }

            get route() {
              return "activeLotteries";
            }

            get text() {
              return i18n("vzekc_verlosung.nav.verlosungen");
            }

            get title() {
              return i18n("vzekc_verlosung.nav.verlosungen");
            }

            get prefixType() {
              return "icon";
            }

            get prefixValue() {
              return "dice";
            }
          };

          const SpendenCategoryLink = class extends BaseCustomSidebarSectionLink {
            get name() {
              return "spenden-category";
            }

            get href() {
              const categoryId = parseInt(
                siteSettings.vzekc_verlosung_donation_category_id,
                10
              );
              const category = site.categories?.find(
                (c) => c.id === categoryId
              );
              return category?.url;
            }

            get text() {
              return i18n("vzekc_verlosung.nav.spenden");
            }

            get title() {
              return i18n("vzekc_verlosung.nav.spenden");
            }

            get prefixType() {
              return "icon";
            }

            get prefixValue() {
              return "hand-holding-heart";
            }
          };

          const ErhaltungsberichteCategoryLink = class extends BaseCustomSidebarSectionLink {
            get name() {
              return "erhaltungsberichte-category";
            }

            get href() {
              const categoryId = parseInt(
                siteSettings.vzekc_verlosung_erhaltungsberichte_category_id,
                10
              );
              const category = site.categories?.find(
                (c) => c.id === categoryId
              );
              return category?.url;
            }

            get text() {
              return i18n("vzekc_verlosung.nav.erhaltungsberichte");
            }

            get title() {
              return i18n("vzekc_verlosung.nav.erhaltungsberichte");
            }

            get prefixType() {
              return "icon";
            }

            get prefixValue() {
              return "file-lines";
            }
          };

          const HistoryLink = class extends BaseCustomSidebarSectionLink {
            get name() {
              return "verlosung-history";
            }

            get route() {
              return "lotteryHistory";
            }

            get text() {
              return i18n("vzekc_verlosung.nav.historie");
            }

            get title() {
              return i18n("vzekc_verlosung.nav.historie");
            }

            get prefixType() {
              return "icon";
            }

            get prefixValue() {
              return "clock-rotate-left";
            }
          };

          return class VerlosungSection extends BaseCustomSidebarSection {
            get name() {
              return "verlosung";
            }

            get text() {
              return i18n("vzekc_verlosung.nav.section_title");
            }

            get collapsedByDefault() {
              return false;
            }

            get links() {
              const links = [];

              // Spendenangebote
              if (siteSettings.vzekc_verlosung_donation_category_id) {
                links.push(new SpendenCategoryLink());
              }

              // Verlosungen (active lotteries)
              links.push(new ActiveLotteriesLink());

              // Erhaltungsberichte
              if (siteSettings.vzekc_verlosung_erhaltungsberichte_category_id) {
                links.push(new ErhaltungsberichteCategoryLink());
              }

              // Verlosungshistorie
              links.push(new HistoryLink());

              return links;
            }
          };
        }
      );
    });
  },
};
