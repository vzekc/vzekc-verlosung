import Component from "@glimmer/component";
import { service } from "@ember/service";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import CreateLotteryModal from "./modal/create-lottery-modal";

/**
 * Button component to create a new lottery (Verlosung)
 *
 * @component NeueVerlosungButton
 * Displays a button in the configured category to start lottery creation
 */
export default class NeueVerlosungButton extends Component {
  @service siteSettings;
  @service modal;
  @service router;

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
      this.siteSettings.vzekc_verlosung_category_id,
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
   * Opens the lottery creation modal
   */
  @action
  openLotteryModal() {
    this.modal.show(CreateLotteryModal, {
      model: {
        categoryId: this.args.category.id,
      },
    });
  }

  <template>
    {{#if this.shouldShow}}
      <DButton
        @action={{this.openLotteryModal}}
        @label="vzekc_verlosung.neue_verlosung"
        @icon="gift"
        class="btn-primary neue-verlosung-button"
      />
    {{/if}}
  </template>
}
