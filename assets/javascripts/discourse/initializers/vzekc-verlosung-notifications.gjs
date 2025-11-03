import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

/**
 * Registers custom notification renderers for lottery notifications
 */
export default apiInitializer((api) => {
  // Register renderer for "lottery published" notifications
  api.registerNotificationTypeRenderer(
    "vzekc_verlosung_published",
    (NotificationTypeBase) => {
      return class extends NotificationTypeBase {
        get icon() {
          return "bullhorn";
        }

        get label() {
          return i18n("notifications.titles.vzekc_verlosung_published");
        }

        get description() {
          return this.notification.fancy_title;
        }

        get linkTitle() {
          return i18n("notifications.titles.vzekc_verlosung_published");
        }
      };
    }
  );

  // Register renderer for "winners drawn" notifications
  api.registerNotificationTypeRenderer(
    "vzekc_verlosung_drawn",
    (NotificationTypeBase) => {
      return class extends NotificationTypeBase {
        get icon() {
          return "trophy";
        }

        get label() {
          return i18n("notifications.titles.vzekc_verlosung_drawn");
        }

        get description() {
          return this.notification.fancy_title;
        }

        get linkTitle() {
          return i18n("notifications.titles.vzekc_verlosung_drawn");
        }
      };
    }
  );

  // Register renderer for "you won" notifications
  api.registerNotificationTypeRenderer(
    "vzekc_verlosung_won",
    (NotificationTypeBase) => {
      return class extends NotificationTypeBase {
        get icon() {
          return "trophy";
        }

        get label() {
          return i18n("notifications.titles.vzekc_verlosung_won");
        }

        get description() {
          // this.notification.data is already an object, not a JSON string
          const data = this.notification.data;
          return data.packet_title || "";
        }

        get linkTitle() {
          return i18n("notifications.titles.vzekc_verlosung_won");
        }
      };
    }
  );

  // Register renderer for "ticket bought" notifications
  api.registerNotificationTypeRenderer(
    "vzekc_verlosung_ticket_bought",
    (NotificationTypeBase) => {
      return class extends NotificationTypeBase {
        get icon() {
          return "ticket";
        }

        get label() {
          const data = this.notification.data;
          return i18n("notifications.titles.vzekc_verlosung_ticket_bought", {
            display_username: data.display_username,
          });
        }

        get description() {
          const data = this.notification.data;
          return data.packet_title || "";
        }

        get linkTitle() {
          const data = this.notification.data;
          return i18n("notifications.titles.vzekc_verlosung_ticket_bought", {
            display_username: data.display_username,
          });
        }
      };
    }
  );

  // Register renderer for "ticket returned" notifications
  api.registerNotificationTypeRenderer(
    "vzekc_verlosung_ticket_returned",
    (NotificationTypeBase) => {
      return class extends NotificationTypeBase {
        get icon() {
          return "ticket";
        }

        get label() {
          const data = this.notification.data;
          return i18n("notifications.titles.vzekc_verlosung_ticket_returned", {
            display_username: data.display_username,
          });
        }

        get description() {
          const data = this.notification.data;
          return data.packet_title || "";
        }

        get linkTitle() {
          const data = this.notification.data;
          return i18n("notifications.titles.vzekc_verlosung_ticket_returned", {
            display_username: data.display_username,
          });
        }
      };
    }
  );

  // Register renderer for "did not win" notifications
  api.registerNotificationTypeRenderer(
    "vzekc_verlosung_did_not_win",
    (NotificationTypeBase) => {
      return class extends NotificationTypeBase {
        get icon() {
          return "times-circle";
        }

        get label() {
          return i18n("notifications.titles.vzekc_verlosung_did_not_win");
        }

        get description() {
          return this.notification.fancy_title;
        }

        get linkTitle() {
          return i18n("notifications.titles.vzekc_verlosung_did_not_win");
        }
      };
    }
  );

  // Register renderer for "lottery ending tomorrow" notifications
  api.registerNotificationTypeRenderer(
    "vzekc_verlosung_ending_tomorrow",
    (NotificationTypeBase) => {
      return class extends NotificationTypeBase {
        get icon() {
          return "clock";
        }

        get label() {
          return i18n("notifications.titles.vzekc_verlosung_ending_tomorrow");
        }

        get description() {
          return this.notification.fancy_title;
        }

        get linkTitle() {
          return i18n("notifications.titles.vzekc_verlosung_ending_tomorrow");
        }
      };
    }
  );
});
