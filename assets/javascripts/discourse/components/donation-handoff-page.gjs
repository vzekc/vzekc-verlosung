import Component from "@glimmer/component";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { next } from "@ember/runloop";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import CreateDonationModal from "./modal/create-donation-modal";

/**
 * Page behind a Herold handoff link: opens the donation offer modal
 * pre-filled from the handed-over email thread, then moves on to the
 * donations list once the modal closes.
 *
 * @component DonationHandoffPage
 * @param {string} token - One-time handoff token
 */
export default class DonationHandoffPage extends Component {
  @service modal;
  @service router;
  @service siteSettings;

  /**
   * Opens the modal in the next run loop: Discourse closes open modals after
   * rendering a route change (clean-dom-on-route-change), which would close a
   * modal opened while this page renders.
   */
  @action
  scheduleModal() {
    next(this, this.openModal);
  }

  /**
   * Shows the modal and navigates to the donations list when it closes
   */
  async openModal() {
    await this.modal.show(CreateDonationModal, {
      model: {
        categoryId: parseInt(
          this.siteSettings.vzekc_verlosung_donation_category_id,
          10
        ),
        handoffToken: this.args.token,
      },
    });
    this.router.transitionTo("activeDonations");
  }

  <template>
    <div class="donation-handoff-page" {{didInsert this.scheduleModal}}>
      {{i18n "vzekc_verlosung.donation_handoff.opening"}}
    </div>
  </template>
}
