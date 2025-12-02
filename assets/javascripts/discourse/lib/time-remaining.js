import { i18n } from "discourse-i18n";

/**
 * Calculates and formats time remaining until a given end date
 *
 * @param {string|Date} endsAt - The end date
 * @returns {string|null} Formatted time remaining string, or null if no end date
 */
export function timeRemaining(endsAt) {
  if (!endsAt) {
    return null;
  }

  const now = new Date();
  const endDate = new Date(endsAt);
  const diffMs = endDate - now;

  if (diffMs <= 0) {
    return i18n("vzekc_verlosung.status.ended");
  }

  const diffMinutes = Math.floor(diffMs / (1000 * 60));
  const diffHours = Math.floor(diffMinutes / 60);
  const diffDays = Math.floor(diffHours / 24);

  const diffSeconds = Math.floor(diffMs / 1000);

  if (diffDays > 1) {
    return i18n("vzekc_verlosung.status.days_remaining", { count: diffDays });
  } else if (diffDays === 1) {
    return i18n("vzekc_verlosung.status.one_day_remaining");
  } else if (diffHours > 1) {
    return i18n("vzekc_verlosung.status.hours_remaining", { count: diffHours });
  } else if (diffHours === 1) {
    return i18n("vzekc_verlosung.status.one_hour_remaining");
  } else if (diffMinutes > 5) {
    return i18n("vzekc_verlosung.status.minutes_remaining", {
      count: diffMinutes,
    });
  } else if (diffMinutes >= 1) {
    const remainingSeconds = diffSeconds % 60;
    return i18n("vzekc_verlosung.status.minutes_seconds_remaining", {
      minutes: diffMinutes,
      seconds: remainingSeconds,
    });
  } else if (diffSeconds > 1) {
    return i18n("vzekc_verlosung.status.seconds_remaining", {
      count: diffSeconds,
    });
  } else {
    return i18n("vzekc_verlosung.status.one_second_remaining");
  }
}
