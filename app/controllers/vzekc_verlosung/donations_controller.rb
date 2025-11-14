# frozen_string_literal: true

module VzekcVerlosung
  # Controller for managing donation offers
  #
  # Roles:
  # - donor: Person who has hardware to give away (not in system)
  # - facilitator: Creates donation offer, finds picker, provides donor contact
  # - picker: Picks up donation, then keeps it or creates lottery
  #
  class DonationsController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in

    # GET /vzekc-verlosung/donations/:id
    #
    # Gets the current state of a donation
    #
    # @param id [Integer] Donation ID
    #
    # @return [JSON] Donation details including current state and lottery link if created
    def show
      donation = Donation.find(params[:id])

      lottery_topic = donation.lottery&.topic
      lottery_data =
        if lottery_topic
          { id: donation.lottery.id, topic_id: lottery_topic.id, url: lottery_topic.url }
        end

      # Use direct association instead of custom field query
      erhaltungsbericht_topic = donation.erhaltungsbericht_topic
      erhaltungsbericht_data =
        if erhaltungsbericht_topic
          { id: erhaltungsbericht_topic.id, url: erhaltungsbericht_topic.url }
        end

      render json: {
               donation: {
                 id: donation.id,
                 state: donation.state,
                 postcode: donation.postcode,
                 topic_id: donation.topic_id,
                 creator_user_id: donation.creator_user_id,
                 published_at: donation.published_at,
                 lottery_id: donation.lottery&.id,
                 lottery: lottery_data,
                 erhaltungsbericht: erhaltungsbericht_data,
               },
             }
    end

    # POST /vzekc-verlosung/donations
    #
    # Creates a new donation in draft state (no topic yet)
    #
    # @param postcode [String] Location postcode for pickup
    #
    # @return [JSON] donation_id for use in composer
    def create
      donation =
        Donation.create!(postcode: create_params[:postcode], creator_user_id: current_user.id)

      render json: success_json.merge(donation_id: donation.id)
    rescue ActiveRecord::RecordInvalid => e
      render json: failed_json.merge(errors: e.record.errors.full_messages),
             status: :unprocessable_entity
    end

    # PUT /vzekc-verlosung/donations/:id/publish
    #
    # Publishes a draft donation (changes state to open)
    #
    # @param id [Integer] Donation ID
    #
    # @return [HTTP 204] No content on success
    def publish
      donation = Donation.find(params[:id])

      unless guardian.can_manage_donation?(donation)
        return(
          render_json_error("You don't have permission to manage this donation", status: :forbidden)
        )
      end

      unless donation.draft?
        return render_json_error("Donation is not in draft state", status: :unprocessable_entity)
      end

      donation.publish!

      head :no_content
    end

    # PUT /vzekc-verlosung/donations/:id/close
    #
    # Closes a donation (manual close by creator)
    #
    # @param id [Integer] Donation ID
    #
    # @return [HTTP 204] No content on success
    def close
      donation = Donation.find(params[:id])

      unless guardian.can_manage_donation?(donation)
        return(
          render_json_error("You don't have permission to manage this donation", status: :forbidden)
        )
      end

      donation.close!

      head :no_content
    end

    private

    def create_params
      params.permit(:postcode)
    end
  end
end
