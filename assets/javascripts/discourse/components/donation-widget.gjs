import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import formatUsername from "discourse/helpers/format-username";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import Composer from "discourse/models/composer";
import { eq, gt } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import AssignOfferModal from "./modal/assign-offer-modal";

/**
 * Donation widget component for managing pickup offers
 *
 * @component DonationWidget
 * Shows donation state, pickup offers from pickers, and action buttons for facilitator
 *
 * Roles:
 * - facilitator: User who created donation, manages offers, provides donor contact
 * - picker: User who offers to pick up donation
 *
 * @param {Object} args.data.post - The post object (passed via renderGlimmer)
 */
export default class DonationWidget extends Component {
  @service currentUser;
  @service appEvents;
  @service composer;
  @service modal;
  @service router;
  @service siteSettings;

  @tracked donationData = null;
  @tracked pickupOffers = [];
  @tracked userOffer = null;
  @tracked loading = true;
  @tracked actionInProgress = false;

  constructor() {
    super(...arguments);
    if (this.shouldShow) {
      this.loadDonationData();
      this.appEvents.on("donation:data-changed", this, this.onDataChanged);
      document.addEventListener("visibilitychange", this.onVisibilityChange);
    } else {
      this.loading = false;
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    if (this.shouldShow) {
      this.appEvents.off("donation:data-changed", this, this.onDataChanged);
      document.removeEventListener("visibilitychange", this.onVisibilityChange);
    }
  }

  @bind
  onVisibilityChange() {
    if (!document.hidden && this.shouldShow) {
      this.loadDonationData();
    }
  }

  /**
   * Get the post object from component args
   *
   * @type {Object}
   */
  get post() {
    return this.args.data?.post;
  }

  @bind
  onDataChanged(postId) {
    if (postId === this.post?.id) {
      this.loadDonationData();
    }
  }

  /**
   * Load donation data including offers
   */
  async loadDonationData() {
    this.loading = true;
    try {
      const initialData = this.post?.donation_data;
      if (!initialData) {
        return;
      }

      // Fetch fresh donation data from backend to get current state
      const donationResult = await ajax(
        `/vzekc-verlosung/donations/${initialData.id}`
      );
      this.donationData = donationResult.donation;

      // Load pickup offers (except for drafts)
      if (this.donationData.state !== "draft") {
        const offersResult = await ajax(
          `/vzekc-verlosung/donations/${this.donationData.id}/pickup-offers`
        );
        this.pickupOffers = offersResult.offers || [];

        // Find user's offer if any
        this.userOffer = this.pickupOffers.find(
          (offer) =>
            offer.user.id === this.currentUser.id &&
            (offer.state === "pending" || offer.state === "assigned")
        );
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * Check if this widget should be shown
   *
   * @type {boolean}
   */
  get shouldShow() {
    return this.currentUser && this.post?.is_donation_post;
  }

  /**
   * Check if user is the donation facilitator
   *
   * @type {boolean}
   */
  get isFacilitator() {
    return (
      this.donationData &&
      this.currentUser.id === this.donationData.creator_user_id
    );
  }

  // Backwards compatibility alias
  get isCreator() {
    return this.isFacilitator;
  }

  /**
   * Check if user can offer to pick up
   *
   * @type {boolean}
   */
  get canOfferPickup() {
    return this.donationData?.state === "open" && !this.userOffer;
  }

  /**
   * Check if user can retract their offer
   * Only possible when donation is still open and offer is pending
   *
   * @type {boolean}
   */
  get canRetractOffer() {
    return (
      this.donationData?.state === "open" &&
      this.userOffer &&
      this.userOffer.state === "pending"
    );
  }

  /**
   * Check if donation is assigned to current user
   *
   * @type {boolean}
   */
  get isAssignedToUser() {
    return (
      this.userOffer &&
      this.userOffer.state === "assigned" &&
      this.donationData?.state === "assigned"
    );
  }

  /**
   * Get the assigned or picked_up offer
   *
   * @type {Object|null}
   */
  get assignedOffer() {
    return this.pickupOffers.find(
      (offer) => offer.state === "assigned" || offer.state === "picked_up"
    );
  }

  /**
   * Get other (pending) offers
   *
   * @type {Array}
   */
  get otherOffers() {
    return this.pickupOffers.filter((offer) => offer.state === "pending");
  }

  /**
   * Check if donation is in a finalized state (assigned, picked_up, or closed)
   *
   * @type {boolean}
   */
  get isFinalizedState() {
    return ["assigned", "picked_up", "closed"].includes(
      this.donationData?.state
    );
  }

  /**
   * Check if lottery was created from this donation
   *
   * @type {boolean}
   */
  get hasLotteryCreated() {
    return this.donationData?.lottery_id != null;
  }

  /**
   * Check if Erhaltungsbericht was written for this donation
   *
   * @type {boolean}
   */
  get hasErhaltungsberichtCreated() {
    return this.donationData?.erhaltungsbericht?.id != null;
  }

  /**
   * Check if current user picked up the donation and needs to take action
   *
   * @type {boolean}
   */
  get needsPickupAction() {
    if (!this.donationData || !this.currentUser) {
      return false;
    }

    // Check if donation is in picked_up or closed state
    if (!["picked_up", "closed"].includes(this.donationData.state)) {
      return false;
    }

    // Don't show next steps if lottery already created
    if (this.hasLotteryCreated) {
      return false;
    }

    // Don't show next steps if Erhaltungsbericht already written
    if (this.hasErhaltungsberichtCreated) {
      return false;
    }

    // Check if current user is the one who picked it up
    const pickedUpOffer = this.pickupOffers.find(
      (offer) => offer.state === "picked_up"
    );

    return pickedUpOffer && pickedUpOffer.user.id === this.currentUser.id;
  }

  /**
   * Offer to pick up this donation
   */
  @action
  async offerPickup() {
    if (this.actionInProgress) {
      return;
    }

    this.actionInProgress = true;

    try {
      await ajax(
        `/vzekc-verlosung/donations/${this.donationData.id}/pickup-offers`,
        {
          type: "POST",
        }
      );

      this.appEvents.trigger("donation:data-changed", this.post.id);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.actionInProgress = false;
    }
  }

  /**
   * Retract pickup offer
   */
  @action
  async retractOffer() {
    if (this.actionInProgress || !this.userOffer) {
      return;
    }

    this.actionInProgress = true;

    try {
      await ajax(`/vzekc-verlosung/pickup-offers/${this.userOffer.id}`, {
        type: "DELETE",
      });

      this.appEvents.trigger("donation:data-changed", this.post.id);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.actionInProgress = false;
    }
  }

  /**
   * Assign donation to a specific picker
   * Opens modal for facilitator to provide donor's contact information
   *
   * @param {Object} offer - The pickup offer from the picker to assign
   */
  @action
  assignOffer(offer) {
    this.modal.show(AssignOfferModal, {
      model: {
        offer,
        donationId: this.donationData.id,
        onAssigned: () => {
          this.appEvents.trigger("donation:data-changed", this.post.id);
        },
      },
    });
  }

  /**
   * Mark donation as picked up
   */
  @action
  async markPickedUp() {
    if (this.actionInProgress || !this.userOffer) {
      return;
    }

    this.actionInProgress = true;

    try {
      await ajax(
        `/vzekc-verlosung/pickup-offers/${this.userOffer.id}/mark-picked-up`,
        {
          type: "PUT",
        }
      );

      this.appEvents.trigger("donation:data-changed", this.post.id);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.actionInProgress = false;
    }
  }

  /**
   * Open composer to write Erhaltungsbericht
   * The erhaltungsbericht_donation_id is passed to the composer and will be stored
   * as a custom field when the topic is created, allowing for a link back to the donation
   */
  @action
  writeErhaltungsbericht() {
    const erhaltungsberichtCategoryId = parseInt(
      this.siteSettings.vzekc_verlosung_erhaltungsberichte_category_id,
      10
    );

    if (!erhaltungsberichtCategoryId) {
      this.appEvents.trigger(
        "modal-body:flash",
        "error",
        "vzekc_verlosung.erhaltungsbericht.category_not_configured"
      );
      return;
    }

    const template =
      this.siteSettings.vzekc_verlosung_erhaltungsbericht_template || "";
    const topic = this.post.topic;

    // Open composer with erhaltungsbericht_donation_id for linking
    // The topic_created hook will store the donation_id as a custom field
    this.composer.open({
      action: Composer.CREATE_TOPIC,
      categoryId: erhaltungsberichtCategoryId,
      title: topic.title,
      reply: template,
      draftKey: `erhaltungsbericht_donation_${this.donationData.id}_${Date.now()}`,
      erhaltungsbericht_donation_id: this.donationData.id,
      skipSimilarTopics: true,
    });
  }

  /**
   * Navigate to lottery creation page with donation data
   */
  @action
  createLottery() {
    if (!this.siteSettings.vzekc_verlosung_enabled) {
      return;
    }

    const topic = this.post.topic;

    this.router.transitionTo("newLottery", {
      queryParams: {
        donation_id: this.donationData.id,
        donation_title: topic.title,
      },
    });
  }

  <template>
    {{#if this.shouldShow}}
      <div class="donation-widget">
        {{#if this.loading}}
          <div class="donation-widget-loading">
            {{icon "spinner"}}
            {{i18n "vzekc_verlosung.ticket.loading"}}
          </div>
        {{else}}
          <div class="donation-header">
            <div class="donation-id">
              <strong>{{i18n
                  "vzekc_verlosung.donation.donation_number"
                }}:</strong>
              {{this.donationData.id}}
            </div>
            <div class="donation-state">
              <strong>{{i18n "vzekc_verlosung.donation.state.title"}}:</strong>
              {{i18n
                (concat
                  "vzekc_verlosung.donation.state." this.donationData.state
                )
              }}
            </div>
          </div>

          {{! Restructured view for assigned/picked_up/closed states }}
          {{#if this.isFinalizedState}}
            {{#if this.assignedOffer}}
              <div class="assigned-offer-section">
                <h4>{{i18n "vzekc_verlosung.donation.assigned_to"}}</h4>
                <div class="assigned-offer-item">
                  <a
                    class="trigger-user-card offer-user-info"
                    data-user-card={{this.assignedOffer.user.username}}
                    title={{this.assignedOffer.user.username}}
                  >
                    {{avatar this.assignedOffer.user imageSize="medium"}}
                    <span class="offer-username">
                      {{formatUsername this.assignedOffer.user.username}}
                    </span>
                  </a>
                  {{! Only show "Zugewiesen" badge when donation is in assigned state }}
                  {{#if (eq this.donationData.state "assigned")}}
                    <span class="offer-state-badge assigned">
                      ({{i18n "vzekc_verlosung.donation.state.assigned"}})
                    </span>
                  {{/if}}
                </div>
              </div>
            {{/if}}

            {{#if (gt this.otherOffers.length 0)}}
              <div class="other-offers-section">
                <h4>{{i18n "vzekc_verlosung.donation.other_offers"}}</h4>
                {{#each this.otherOffers as |offer|}}
                  <div class="other-offer-item">
                    <a
                      class="trigger-user-card offer-user-info"
                      data-user-card={{offer.user.username}}
                      title={{offer.user.username}}
                    >
                      {{avatar offer.user imageSize="medium"}}
                      <span class="offer-username">
                        {{formatUsername offer.user.username}}
                      </span>
                    </a>
                  </div>
                {{/each}}
              </div>
            {{/if}}
          {{else}}
            {{! Standard view for open/draft states }}
            {{#if (gt this.pickupOffers.length 0)}}
              <div class="pickup-offers-list">
                <h4>{{i18n "vzekc_verlosung.donation.pickup_offers"}}</h4>
                {{#each this.pickupOffers as |offer|}}
                  <div class="pickup-offer-item">
                    <div class="offer-user-line">
                      <a
                        class="trigger-user-card offer-user-info"
                        data-user-card={{offer.user.username}}
                        title={{offer.user.username}}
                      >
                        {{avatar offer.user imageSize="medium"}}
                        <span class="offer-username">
                          {{formatUsername offer.user.username}}
                        </span>
                      </a>
                      {{#if (eq offer.state "assigned")}}
                        <span class="offer-state-badge assigned">
                          ({{i18n "vzekc_verlosung.donation.state.assigned"}})
                        </span>
                      {{/if}}
                      {{#if (eq offer.state "picked_up")}}
                        <span class="offer-state-badge picked-up">
                          ({{i18n "vzekc_verlosung.donation.state.picked_up"}})
                        </span>
                      {{/if}}
                    </div>
                    {{#if this.isCreator}}
                      {{#if (eq this.donationData.state "open")}}
                        <DButton
                          @action={{fn this.assignOffer offer}}
                          @label="vzekc_verlosung.donation.assign"
                          @icon="user-plus"
                          @disabled={{this.actionInProgress}}
                          class="btn-small assign-offer-button"
                        />
                      {{/if}}
                    {{/if}}
                  </div>
                {{/each}}
              </div>
            {{else}}
              <div class="no-offers">
                {{i18n "vzekc_verlosung.donation.no_offers"}}
              </div>
            {{/if}}
          {{/if}}

          {{! Offer pickup button - shown below the list }}
          {{#if this.canOfferPickup}}
            <div class="donation-actions">
              <DButton
                @action={{this.offerPickup}}
                @label="vzekc_verlosung.donation.offer_pickup"
                @icon="hand-point-up"
                @disabled={{this.actionInProgress}}
                class="btn-primary offer-pickup-button"
              />
            </div>
          {{/if}}

          {{#if this.canRetractOffer}}
            <div class="donation-user-offer">
              <div class="user-offer-notice">
                {{icon "check"}}
                {{i18n "vzekc_verlosung.donation.your_offer"}}
              </div>
              <DButton
                @action={{this.retractOffer}}
                @label="vzekc_verlosung.donation.retract_offer"
                @icon="arrow-rotate-left"
                @disabled={{this.actionInProgress}}
                class="btn-danger retract-offer-button"
              />
            </div>
          {{/if}}

          {{#if this.isAssignedToUser}}
            <div class="donation-assigned-to-user">
              <div class="assigned-notice">
                {{icon "circle-check"}}
                {{i18n "vzekc_verlosung.donation.assigned_to_you"}}
              </div>
              <DButton
                @action={{this.markPickedUp}}
                @label="vzekc_verlosung.donation.mark_picked_up"
                @icon="check"
                @disabled={{this.actionInProgress}}
                class="btn-primary mark-picked-up-button"
              />
            </div>
          {{/if}}

          {{#if this.hasLotteryCreated}}
            <div class="donation-lottery-created">
              <h4>{{i18n "vzekc_verlosung.donation.lottery_created"}}</h4>
              <p>{{i18n
                  "vzekc_verlosung.donation.lottery_created_description"
                }}</p>
              <a
                href={{this.donationData.lottery.url}}
                class="btn btn-primary lottery-link-button"
              >
                {{icon "gift"}}
                {{i18n "vzekc_verlosung.donation.view_lottery"}}
              </a>
            </div>
          {{else if this.hasErhaltungsberichtCreated}}
            <div class="donation-erhaltungsbericht-link">
              {{icon "file-lines"}}
              <a href={{this.donationData.erhaltungsbericht.url}}>
                {{i18n "vzekc_verlosung.donation.view_erhaltungsbericht"}}
              </a>
            </div>
          {{else if this.needsPickupAction}}
            <div class="donation-next-steps">
              <h4>{{i18n "vzekc_verlosung.donation.next_steps"}}</h4>
              <p>{{i18n "vzekc_verlosung.donation.next_steps_description"}}</p>
              <div class="next-steps-buttons">
                <DButton
                  @action={{this.writeErhaltungsbericht}}
                  @label="vzekc_verlosung.donation.write_erhaltungsbericht"
                  @icon="pen"
                  class="btn-primary write-erhaltungsbericht-button"
                />
                <DButton
                  @action={{this.createLottery}}
                  @label="vzekc_verlosung.donation.create_lottery_action"
                  @icon="gift"
                  class="btn-primary create-lottery-button"
                />
              </div>
            </div>
          {{/if}}
        {{/if}}
      </div>
    {{/if}}
  </template>
}
