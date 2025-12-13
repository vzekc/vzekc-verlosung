import { tracked } from "@glimmer/tracking";
import Service, { service } from "@ember/service";

const MODE_ABSOLUTE = "absolute";
const MODE_RELATIVE = "relative";
const FIELD_NAME = "vzekc_lottery_list_date_mode";

// Combined sort modes: "ends_soon" (by end date, soonest first) or "newest" (by creation, newest first)
const SORT_ENDS_SOON = "ends_soon";
const SORT_NEWEST = "newest";
const SORT_MODE_FIELD = "vzekc_lottery_list_sort_mode";

/**
 * Service to manage lottery list display preferences
 *
 * @service lotteryDisplayMode
 * Provides access to user preferences for lottery list:
 * - displayMode: "absolute" or "relative" for date display
 * - sortMode: "ends_soon" or "newest" for sorting
 */
export default class LotteryDisplayModeService extends Service {
  @service currentUser;

  // Tracked properties - only set when user changes via UI
  @tracked _displayMode = null;
  @tracked _sortMode = null;

  /**
   * Get the current display mode
   *
   * @returns {string} "absolute" or "relative"
   */
  get displayMode() {
    // Return tracked value if user has changed it this session
    if (this._displayMode !== null) {
      return this._displayMode;
    }

    // Default for anonymous users
    if (!this.currentUser) {
      return MODE_ABSOLUTE;
    }

    // Read from custom_fields (don't cache in tracked property during render)
    const savedMode = this.currentUser.custom_fields?.[FIELD_NAME];
    return savedMode === MODE_RELATIVE ? MODE_RELATIVE : MODE_ABSOLUTE;
  }

  /**
   * Check if absolute mode is active
   *
   * @returns {boolean} true if absolute mode
   */
  get isAbsoluteMode() {
    return this.displayMode === MODE_ABSOLUTE;
  }

  /**
   * Check if relative mode is active
   *
   * @returns {boolean} true if relative mode
   */
  get isRelativeMode() {
    return this.displayMode === MODE_RELATIVE;
  }

  /**
   * Set the display mode and save to user profile
   *
   * @param {string} mode - "absolute" or "relative"
   */
  async setMode(mode) {
    if (mode !== MODE_ABSOLUTE && mode !== MODE_RELATIVE) {
      return;
    }

    if (!this.currentUser) {
      return;
    }

    this._displayMode = mode;

    if (!this.currentUser.custom_fields) {
      this.currentUser.custom_fields = {};
    }
    this.currentUser.custom_fields[FIELD_NAME] = mode;

    try {
      // Must pass "custom_fields" as the field name, not the individual key
      await this.currentUser.save(["custom_fields"]);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to save display mode preference:", error);
    }
  }

  /**
   * Toggle between absolute and relative modes
   */
  async toggleMode() {
    const newMode = this.isAbsoluteMode ? MODE_RELATIVE : MODE_ABSOLUTE;
    await this.setMode(newMode);
  }

  // ==================== Sort Mode ====================

  /**
   * Get the current sort mode
   *
   * @returns {string} "ends_soon" or "newest"
   */
  get sortMode() {
    if (this._sortMode !== null) {
      return this._sortMode;
    }

    if (!this.currentUser) {
      return SORT_ENDS_SOON;
    }

    const savedMode = this.currentUser.custom_fields?.[SORT_MODE_FIELD];
    return savedMode === SORT_NEWEST ? SORT_NEWEST : SORT_ENDS_SOON;
  }

  /**
   * @returns {boolean} true if sorting by end date (soonest first)
   */
  get isSortEndsSoon() {
    return this.sortMode === SORT_ENDS_SOON;
  }

  /**
   * @returns {boolean} true if sorting by creation date (newest first)
   */
  get isSortNewest() {
    return this.sortMode === SORT_NEWEST;
  }

  /**
   * Set the sort mode and save to user profile
   *
   * @param {string} mode - "ends_soon" or "newest"
   */
  async setSortMode(mode) {
    if (mode !== SORT_ENDS_SOON && mode !== SORT_NEWEST) {
      return;
    }

    if (!this.currentUser) {
      return;
    }

    this._sortMode = mode;

    if (!this.currentUser.custom_fields) {
      this.currentUser.custom_fields = {};
    }
    this.currentUser.custom_fields[SORT_MODE_FIELD] = mode;

    try {
      await this.currentUser.save(["custom_fields"]);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to save sort mode preference:", error);
    }
  }

  /**
   * Sort an array of lotteries based on current preferences
   *
   * @param {Array} lotteries - Array of lottery objects
   * @returns {Array} Sorted array
   */
  sortLotteries(lotteries) {
    if (!lotteries?.length) {
      return lotteries;
    }

    const mode = this.sortMode;

    return [...lotteries].sort((a, b) => {
      if (mode === SORT_NEWEST) {
        // Newest first: by creation date, descending
        return new Date(b.created_at) - new Date(a.created_at);
      } else {
        // Ends soon: by end date, ascending (soonest first)
        return new Date(a.ends_at) - new Date(b.ends_at);
      }
    });
  }
}
