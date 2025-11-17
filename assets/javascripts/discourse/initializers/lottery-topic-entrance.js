import { apiInitializer } from "discourse/lib/api";

/**
 * Override topic entrance for lottery topics to always show the main post
 *
 * In lottery topics, the main post contains the lottery summary with all packets.
 * This is essential information that users need to see, so we override Discourse's
 * default behavior (jumping to last unread or end of thread) to always show post #1.
 */
export default apiInitializer((api) => {
  api.registerCustomLastUnreadUrlCallback((context) => {
    // Check if this topic is a lottery (has lottery_state custom field)
    if (context.lottery_state) {
      // Always link to the main post (post #1) for lottery topics
      return context.urlForPostNumber(1);
    }
  });
});
