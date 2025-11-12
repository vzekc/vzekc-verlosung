import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import CreateDonationModal from "./modal/create-donation-modal";

/**
 * Button component to create a new donation offer
 *
 * @component NeueSpendeButton
 * Displays a button in the configured donation category to start donation creation
 */
export default class NeueSpendeButton extends Component {
  @service siteSettings;
  @service modal;

  /**
   * Check if button should be shown in current category
   *
   * @type {boolean}
   */
  get shouldShow() {
    if (!this.siteSettings.vzekc_verlosung_enabled) {
      return false;
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
   * Opens the donation creation modal
   */
  @action
  openDonationModal() {
    this.modal.show(CreateDonationModal, {
      model: {
        categoryId: this.args.category.id,
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
