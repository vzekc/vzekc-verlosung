# frozen_string_literal: true

module VzekcVerlosung
  # Controller for managing lottery interest expressions on donations
  #
  # Users can express interest in participating in a potential lottery
  # for a donation, visible to everyone.
  #
  class LotteryInterestsController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in

    # POST /vzekc-verlosung/donations/:donation_id/lottery-interests
    #
    # Express interest in a potential lottery for a donation
    #
    # @param donation_id [Integer] Donation ID
    #
    # @return [JSON] The created lottery interest
    def create
      donation = Donation.find(params[:donation_id])

      unless guardian.can_express_lottery_interest?(donation)
        return(
          render_json_error("You cannot express interest in this donation", status: :forbidden)
        )
      end

      interest = LotteryInterest.create!(donation_id: donation.id, user_id: current_user.id)

      NotificationService.notify(
        :new_lottery_interest,
        recipient: donation.facilitator,
        context: {
          donation: donation,
          interested_user: current_user,
        },
      )

      render json: success_json.merge(interest: serialize_interest(interest))
    rescue ActiveRecord::RecordInvalid => e
      render json: failed_json.merge(errors: e.record.errors.full_messages),
             status: :unprocessable_entity
    end

    # DELETE /vzekc-verlosung/lottery-interests/:id
    #
    # Retract lottery interest
    #
    # @param id [Integer] Lottery interest ID
    #
    # @return [HTTP 204] No content on success
    def destroy
      interest = LotteryInterest.find(params[:id])

      unless interest.user_id == current_user.id
        return(
          render_json_error(
            "You don't have permission to retract this interest",
            status: :forbidden,
          )
        )
      end

      interest.destroy!

      head :no_content
    end

    # GET /vzekc-verlosung/donations/:donation_id/lottery-interests
    #
    # Lists lottery interests for a donation
    #
    # @param donation_id [Integer] Donation ID
    #
    # @return [JSON] Array of lottery interests
    def index
      donation = Donation.find(params[:donation_id])
      interests = donation.lottery_interests.includes(:user).order(created_at: :asc)

      render json: { interests: interests.map { |i| serialize_interest(i) } }
    end

    private

    # Serialize a lottery interest for JSON response
    #
    # @param interest [LotteryInterest] The interest to serialize
    #
    # @return [Hash] Serialized interest data
    def serialize_interest(interest)
      {
        id: interest.id,
        user: {
          id: interest.user.id,
          username: interest.user.username,
          name: interest.user.name,
          avatar_template: interest.user.avatar_template,
        },
        created_at: interest.created_at,
      }
    end
  end
end
