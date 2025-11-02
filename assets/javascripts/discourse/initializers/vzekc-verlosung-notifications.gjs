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
          return i18n("vzekc_verlosung.notifications.lottery_published", {
            topic_title: this.notification.fancy_title,
          });
        }

        get description() {
          return "";
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
          return i18n("vzekc_verlosung.notifications.lottery_drawn", {
            topic_title: this.notification.fancy_title,
          });
        }

        get description() {
          return "";
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
          // this.notification.data is already an object, not a JSON string
          const data = this.notification.data;
          return i18n("vzekc_verlosung.notifications.lottery_won", {
            packet_title: data.packet_title || "",
            topic_title: this.notification.fancy_title,
          });
        }

        get description() {
          return "";
        }

        get linkTitle() {
          return i18n("notifications.titles.vzekc_verlosung_won");
        }
      };
    }
  );
});
