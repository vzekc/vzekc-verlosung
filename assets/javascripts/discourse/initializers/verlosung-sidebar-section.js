import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

export default {
  name: "verlosung-sidebar-section",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    const site = container.lookup("service:site");
    const currentUser = container.lookup("service:current-user");

    if (!siteSettings.vzekc_verlosung_enabled) {
      return;
    }

    // Check if current user is a merch handler
    const merchHandlersGroupName =
      siteSettings.vzekc_verlosung_merch_handlers_group_name;
    const isMerchHandler =
      currentUser &&
      merchHandlersGroupName &&
      currentUser.groups?.some((g) => g.name === merchHandlersGroupName);

    withPluginApi((api) => {
      api.addSidebarSection(
        (BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
          const ActiveLotteriesLink = class extends BaseCustomSidebarSectionLink {
            get name() {
              return "lotteries";
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

          const ActiveDonationsLink = class extends BaseCustomSidebarSectionLink {
            get name() {
              return "active-donations";
            }

            get route() {
              return "activeDonations";
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

          const MerchPacketsLink = class extends BaseCustomSidebarSectionLink {
            get name() {
              return "merch-packets";
            }

            get route() {
              return "merchPackets";
            }

            get text() {
              return i18n("vzekc_verlosung.nav.merch_packets");
            }

            get title() {
              return i18n("vzekc_verlosung.nav.merch_packets");
            }

            get prefixType() {
              return "icon";
            }

            get prefixValue() {
              return "truck";
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
              links.push(new ActiveDonationsLink());

              // Verlosungen (active lotteries)
              links.push(new ActiveLotteriesLink());

              // Erhaltungsberichte
              if (siteSettings.vzekc_verlosung_erhaltungsberichte_category_id) {
                links.push(new ErhaltungsberichteCategoryLink());
              }

              // Verlosungshistorie
              links.push(new HistoryLink());

              // Merch-Pakete (only for merch handlers)
              if (isMerchHandler) {
                links.push(new MerchPacketsLink());
              }

              return links;
            }
          };
        }
      );
    });
  },
};
