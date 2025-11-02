import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

/**
 * Customizes rendering for lottery notifications.
 * Since we use the generic :custom notification type, we detect lottery notifications
 * by checking the notification_type field in the notification data.
 */
export default apiInitializer((api) => {
  // Override the custom notification renderer to handle lottery notifications
  api.registerNotificationTypeRenderer("custom", (NotificationTypeBase) => {
    return class extends NotificationTypeBase {
      get icon() {
        const data = this.notificationData;
        if (data?.notification_type === "vzekc_verlosung_published") {
          return "bullhorn";
        }
        if (
          data?.notification_type === "vzekc_verlosung_drawn" ||
          data?.notification_type === "vzekc_verlosung_won"
        ) {
          return "trophy";
        }
        // Default custom notification icon
        return super.icon || "bell";
      }

      get label() {
        const data = this.notificationData;

        // Handle lottery notifications
        if (data?.notification_type === "vzekc_verlosung_published") {
          return i18n("vzekc_verlosung.notifications.lottery_published", {
            topic_title: this.notification.fancy_title,
          });
        }
        if (data?.notification_type === "vzekc_verlosung_drawn") {
          return i18n("vzekc_verlosung.notifications.lottery_drawn", {
            topic_title: this.notification.fancy_title,
          });
        }
        if (data?.notification_type === "vzekc_verlosung_won") {
          return i18n("vzekc_verlosung.notifications.lottery_won", {
            packet_title: data.packet_title || "",
            topic_title: this.notification.fancy_title,
          });
        }

        // Default custom notification rendering
        return super.label;
      }

      get description() {
        const data = this.notificationData;

        // Lottery notifications don't need description
        if (data?.notification_type?.startsWith("vzekc_verlosung_")) {
          return "";
        }

        // Default custom notification description
        return super.description;
      }

      get linkTitle() {
        const data = this.notificationData;

        if (data?.notification_type === "vzekc_verlosung_published") {
          return i18n("notifications.titles.vzekc_verlosung_published");
        }
        if (data?.notification_type === "vzekc_verlosung_drawn") {
          return i18n("notifications.titles.vzekc_verlosung_drawn");
        }
        if (data?.notification_type === "vzekc_verlosung_won") {
          return i18n("notifications.titles.vzekc_verlosung_won");
        }

        // Default custom notification link title
        return super.linkTitle;
      }

      get notificationData() {
        try {
          return JSON.parse(this.notification.data);
        } catch {
          return {};
        }
      }
    };
  });
});
