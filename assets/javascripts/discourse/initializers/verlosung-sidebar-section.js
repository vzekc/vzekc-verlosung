import { ajax } from "discourse/lib/ajax";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

const newContentState = {
  donations: false,
  lotteries: false,
  erhaltungsberichte: false,
  merch_packets: false,
  has_won_packets: false,
};

const LINK_SELECTORS = {
  donations: '.sidebar-section-link[data-link-name="active-donations"]',
  lotteries: '.sidebar-section-link[data-link-name="lotteries"]',
  erhaltungsberichte:
    '.sidebar-section-link[data-link-name="erhaltungsberichte-category"]',
  merch_packets: '.sidebar-section-link[data-link-name="merch-packets"]',
};

const INDICATOR_STYLE = `
  content: "";
  display: inline-block;
  width: 8px;
  height: 8px;
  margin-left: 6px;
  background-color: var(--tertiary);
  border-radius: 50%;
  vertical-align: middle;
`;

let indicatorStyleEl = null;

function updateIndicatorStyles() {
  if (!indicatorStyleEl) {
    indicatorStyleEl = document.createElement("style");
    indicatorStyleEl.id = "vzekc-new-content-indicators";
    document.head.appendChild(indicatorStyleEl);
  }

  const rules = [];
  const wrapper = ".sidebar-section-wrapper[data-section-name='verlosung']";

  for (const [key, selector] of Object.entries(LINK_SELECTORS)) {
    if (newContentState[key]) {
      rules.push(
        `${wrapper} ${selector} .sidebar-section-link-content-text::after { ${INDICATOR_STYLE} }`
      );
    }
  }

  indicatorStyleEl.textContent = rules.join("\n");
}

function fetchNewContentStatus() {
  return ajax("/vzekc-verlosung/has-new-content.json")
    .then((result) => {
      newContentState.donations = result.donations;
      newContentState.lotteries = result.lotteries;
      newContentState.erhaltungsberichte = result.erhaltungsberichte;
      newContentState.merch_packets = result.merch_packets;
      newContentState.has_won_packets = result.has_won_packets;
      updateIndicatorStyles();
    })
    .catch(() => {});
}

export default {
  name: "verlosung-sidebar-section",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    const site = container.lookup("service:site");
    const currentUser = container.lookup("service:current-user");

    if (!siteSettings.vzekc_verlosung_enabled) {
      return;
    }

    const merchHandlersGroupName =
      siteSettings.vzekc_verlosung_merch_handlers_group_name;
    const isMerchHandler =
      currentUser &&
      merchHandlersGroupName &&
      currentUser.groups?.some((g) => g.name === merchHandlersGroupName);

    const erhaltungsberichteCategoryId = parseInt(
      siteSettings.vzekc_verlosung_erhaltungsberichte_category_id,
      10
    );
    const erhaltungsberichteCategory = site.categories?.find(
      (c) => c.id === erhaltungsberichteCategoryId
    );
    const erhaltungsberichteCategoryUrl = erhaltungsberichteCategory?.url;

    if (currentUser) {
      const messageBus = container.lookup("service:message-bus");

      fetchNewContentStatus();

      messageBus.subscribe("/vzekc-verlosung/new-content", (data) => {
        if (data.type && data.type in newContentState) {
          newContentState[data.type] = data.has_new;
          updateIndicatorStyles();
        }
      });
    }

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
              return erhaltungsberichteCategoryUrl;
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

          const MyWinsLink = class extends BaseCustomSidebarSectionLink {
            get name() {
              return "my-wins";
            }

            get href() {
              return `/u/${currentUser.username}/verlosungen?tab=won`;
            }

            get text() {
              return i18n("vzekc_verlosung.nav.meine_gewinne");
            }

            get title() {
              return i18n("vzekc_verlosung.nav.meine_gewinne");
            }

            get prefixType() {
              return "icon";
            }

            get prefixValue() {
              return "trophy";
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

              links.push(new ActiveDonationsLink());
              links.push(new ActiveLotteriesLink());

              if (siteSettings.vzekc_verlosung_erhaltungsberichte_category_id) {
                links.push(new ErhaltungsberichteCategoryLink());
              }

              links.push(new HistoryLink());

              if (isMerchHandler) {
                links.push(new MerchPacketsLink());
              }

              if (currentUser && newContentState.has_won_packets) {
                links.push(new MyWinsLink());
              }

              return links;
            }
          };
        }
      );
    });
  },
};
