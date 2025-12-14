import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import CreateDonationModal from "./modal/create-donation-modal";

/**
 * Button component to create a new donation offer
 *
 * @component NeueSpendeButton
 * @param {boolean} [forceShow] - Force button to show regardless of category
 * Displays a button in the configured donation category to start donation creation
 */
export default class NeueSpendeButton extends Component {
  @service siteSettings;
  @service modal;

  /**
   * Check if button should be shown
   * Button shows if:
   * - @forceShow is true (for pages like active-donations), or
   * - Current category matches configured donation category
   *
   * @type {boolean}
   */
  get shouldShow() {
    if (!this.siteSettings.vzekc_verlosung_enabled) {
      return false;
    }

    if (this.args.forceShow) {
      return true;
    }

    const configuredCategoryId = parseInt(
      this.siteSettings.vzekc_verlosung_donation_category_id,
      10
    );
    const currentCategoryId = this.args.category?.id;

    return (
      configuredCategoryId &&
      currentCategoryId &&
      configuredCategoryId === currentCategoryId
    );
  }

  /**
   * Get the category ID for donation creation
   * Uses passed category or falls back to configured donation category
   *
   * @type {number}
   */
  get categoryId() {
    if (this.args.category?.id) {
      return this.args.category.id;
    }
    return parseInt(this.siteSettings.vzekc_verlosung_donation_category_id, 10);
  }

  /**
   * Opens the donation creation modal
   */
  @action
  openDonationModal() {
    this.modal.show(CreateDonationModal, {
      model: {
        categoryId: this.categoryId,
      },
    });
  }

  <template>
    {{#if this.shouldShow}}
      <DButton
        @action={{this.openDonationModal}}
        @label="vzekc_verlosung.donation.neue_spende"
        @icon="gift"
        class="btn-primary neue-spende-button"
      />
    {{/if}}
  </template>
}
