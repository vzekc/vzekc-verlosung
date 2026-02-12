# frozen_string_literal: true

module VzekcVerlosung
  # Controller for managing pickup offers on donations
  #
  # Roles:
  # - facilitator: Creates donation offer, assigns to picker
  # - picker: Makes pickup offer, receives donor contact info when assigned
  #
  class PickupOffersController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in

    # POST /vzekc-verlosung/donations/:donation_id/pickup-offers
    #
    # Creates a new pickup offer for a donation (picker volunteers)
    #
    # @param donation_id [Integer] Donation ID
    # @param notes [String] Optional notes from the picker
    #
    # @return [JSON] The created pickup offer
    def create
      donation = Donation.find(params[:donation_id])

      unless guardian.can_offer_pickup?(donation)
        return render_json_error("You cannot offer to pick up this donation", status: :forbidden)
      end

      offer =
        PickupOffer.create!(
          donation_id: donation.id,
          user_id: current_user.id,
          notes: create_params[:notes],
        )

      render json: success_json.merge(offer: serialize_offer(offer))
    rescue ActiveRecord::RecordInvalid => e
      render json: failed_json.merge(errors: e.record.errors.full_messages),
             status: :unprocessable_entity
    end

    # DELETE /vzekc-verlosung/pickup-offers/:id
    #
    # Retracts a pickup offer
    #
    # @param id [Integer] Pickup offer ID
    #
    # @return [HTTP 204] No content on success
    def destroy
      offer = PickupOffer.find(params[:id])

      unless offer.user_id == current_user.id
        return(
          render_json_error("You don't have permission to retract this offer", status: :forbidden)
        )
      end

      offer.retract!

      head :no_content
    end

    # GET /vzekc-verlosung/donations/:donation_id/pickup-offers
    #
    # Lists pickup offers for a donation
    #
    # @param donation_id [Integer] Donation ID
    #
    # @return [JSON] Array of pickup offers
    def index
      donation = Donation.find(params[:donation_id])
      # Show all offers for closed/picked_up donations, only active ones for open/assigned
      offers =
        if %w[closed picked_up].include?(donation.state)
          donation.pickup_offers.includes(:user).order(created_at: :asc)
        else
          donation.pickup_offers.includes(:user).active.order(created_at: :asc)
        end

      render json: { offers: offers.map { |o| serialize_offer(o) } }
    end

    # PUT /vzekc-verlosung/pickup-offers/:id/assign
    #
    # Assigns the donation to a specific picker
    # Facilitator provides donor's contact information which is sent to picker via PM
    #
    # @param id [Integer] Pickup offer ID
    # @param contact_info [String] Donor's contact information provided by facilitator
    #
    # @return [HTTP 204] No content on success
    def assign
      offer = PickupOffer.find(params[:id])
      donation = offer.donation

      unless guardian.can_manage_donation?(donation)
        return(
          render_json_error("You don't have permission to assign this donation", status: :forbidden)
        )
      end

      unless donation.open?
        return render_json_error("Donation is not in open state", status: :unprocessable_entity)
      end

      contact_info = assign_params[:contact_info]
      if contact_info.blank?
        return(render_json_error("Contact information is required", status: :unprocessable_entity))
      end

      donation.assign_to!(offer, contact_info: contact_info)

      head :no_content
    end

    # PUT /vzekc-verlosung/pickup-offers/:id/mark-picked-up
    #
    # Marks a donation as picked up (only callable by the assigned picker)
    #
    # @param id [Integer] Pickup offer ID
    #
    # @return [HTTP 204] No content on success
    def mark_picked_up
      offer = PickupOffer.find(params[:id])
      donation = offer.donation

      # Only the assigned picker can confirm pickup
      unless offer.user_id == current_user.id && offer.assigned?
        return render_json_error("You don't have permission to confirm pickup", status: :forbidden)
      end

      unless donation.assigned?
        return render_json_error("Donation is not in assigned state", status: :unprocessable_entity)
      end

      donation.mark_picked_up!

      if donation.merch_packet&.pending?
        handler_ids = VzekcVerlosung.merch_handler_user_ids
        if handler_ids.any?
          VzekcVerlosung.notify_new_content("merch_packets", user_ids: handler_ids)
        end
      end

      head :no_content
    end

    private

    def create_params
      params.permit(:notes)
    end

    def assign_params
      params.permit(:contact_info)
    end

    # Serialize a pickup offer for JSON response
    #
    # @param offer [PickupOffer] The offer to serialize
    #
    # @return [Hash] Serialized offer data
    def serialize_offer(offer)
      {
        id: offer.id,
        user: {
          id: offer.user.id,
          username: offer.user.username,
          name: offer.user.name,
          avatar_template: offer.user.avatar_template,
        },
        state: offer.state,
        notes: offer.notes,
        created_at: offer.created_at,
        assigned_at: offer.assigned_at,
        picked_up_at: offer.picked_up_at,
      }
    end
  end
end
