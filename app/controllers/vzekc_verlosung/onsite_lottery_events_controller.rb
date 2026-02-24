# frozen_string_literal: true

module VzekcVerlosung
  class OnsiteLotteryEventsController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in

    # GET /vzekc-verlosung/onsite-lottery-events/current
    #
    # Returns the current (next future) onsite lottery event, or null
    #
    # @return [JSON] { event: { id, name, event_date, donations_count } | null }
    def current
      event = OnsiteLotteryEvent.current_event

      if event
        render json: {
                 event: {
                   id: event.id,
                   name: event.name,
                   event_date: event.event_date,
                   donations_count: event.donations.count,
                 },
               }
      else
        render json: { event: nil }
      end
    end

    # POST /vzekc-verlosung/onsite-lottery-events
    #
    # Creates a new onsite lottery event (only if no future event exists)
    #
    # @param name [String] Event name
    # @param event_date [String] Event date (YYYY-MM-DD)
    #
    # @return [JSON] { event: { id, name, event_date } }
    def create
      existing = OnsiteLotteryEvent.current_event
      if existing
        return(
          render_json_error(
            "A future onsite lottery event already exists",
            status: :unprocessable_entity,
          )
        )
      end

      event =
        OnsiteLotteryEvent.create!(
          name: params[:name],
          event_date: params[:event_date],
          created_by_user_id: current_user.id,
        )

      render json: {
               event: {
                 id: event.id,
                 name: event.name,
                 event_date: event.event_date,
               },
             },
             status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: failed_json.merge(errors: e.record.errors.full_messages),
             status: :unprocessable_entity
    end

    # POST /vzekc-verlosung/donations/:donation_id/assign-onsite-lottery
    #
    # Marks a donation for an onsite lottery event.
    # Accepts either event_id (existing event) OR event_name + event_date (create new).
    #
    # @param donation_id [Integer] The donation ID
    # @param event_id [Integer] Optional: existing event ID
    # @param event_name [String] Optional: name for new event
    # @param event_date [String] Optional: date for new event (YYYY-MM-DD)
    #
    # @return [HTTP 204] No content on success
    def assign_donation
      donation = Donation.find(params[:donation_id])

      # Validate current user is the picker
      assigned_offer =
        donation.pickup_offers.find_by(user_id: current_user.id, state: %w[assigned picked_up])
      unless assigned_offer
        return(
          render_json_error("You must be the assigned picker for this donation", status: :forbidden)
        )
      end

      # Validate donation doesn't already have an outcome
      if donation.pickup_action_completed?
        return(
          render_json_error(
            "This donation already has an outcome assigned",
            status: :unprocessable_entity,
          )
        )
      end

      # Find or create the event
      event =
        if params[:event_id].present?
          OnsiteLotteryEvent.find(params[:event_id])
        else
          # Create new event inline (only if no future event exists)
          existing = OnsiteLotteryEvent.current_event
          if existing
            existing
          else
            OnsiteLotteryEvent.create!(
              name: params[:event_name],
              event_date: params[:event_date],
              created_by_user_id: current_user.id,
            )
          end
        end

      donation.update!(onsite_lottery_event_id: event.id)

      head :no_content
    rescue ActiveRecord::RecordInvalid => e
      render json: failed_json.merge(errors: e.record.errors.full_messages),
             status: :unprocessable_entity
    end
  end
end
