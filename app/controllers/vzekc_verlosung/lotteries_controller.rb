# frozen_string_literal: true

module VzekcVerlosung
  # Controller for handling lottery creation
  class LotteriesController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in, except: [:silence_reminders_page]

    # GET /vzekc_verlosung/silence-reminders/:topic_id
    #
    # Serves the Discourse app shell so the Ember route can handle
    # the silence-reminders page on the client side.
    # Needed because PM links trigger full page loads.
    def silence_reminders_page
      render html: "", layout: true
    end

    # POST /vzekc_verlosung/lotteries
    #
    # Creates a new lottery with main topic and packet topics
    #
    # @param title [String] Title of the main lottery topic
    # @param duration_days [Integer] Duration in days (7-28)
    # @param category_id [Integer] Category ID where topics should be created
    # @param packets [Array<Hash>] Array of packet data with title
    #
    # @return [JSON] Success with main_topic data or error
    def create
      Rails.logger.info "=== LOTTERY CREATE START ==="
      Rails.logger.info "Params: #{params.inspect}"
      Rails.logger.info "Create params: #{create_params.inspect}"

      result =
        VzekcVerlosung::CreateLottery.call(
          params: create_params.to_unsafe_h,
          user: current_user,
          guardian: guardian,
        )

      Rails.logger.info "Result success: #{result.success?}"

      if result.success?
        render json: success_json.merge(main_topic: serialize_topic(result.main_topic))
      else
        Rails.logger.error "Result failure: #{result.inspect}"

        errors = []

        # Extract validation errors from contract if present
        if result["result.contract.default"]&.failure?
          contract_errors = result["result.contract.default"][:errors]
          Rails.logger.error "Contract errors: #{contract_errors.full_messages.inspect}"
          errors = contract_errors.full_messages
          # Check for step errors (like create_main_topic)
        elsif result["result.step.create_main_topic"]&.failure?
          step_error = result["result.step.create_main_topic"][:error]
          Rails.logger.error "Step error: #{step_error}"
          errors = [step_error]
          # Check for packet creation errors
        elsif result["result.step.create_packet_topics"]&.failure?
          step_error = result["result.step.create_packet_topics"][:error]
          Rails.logger.error "Packet step error: #{step_error}"
          errors = [step_error]
        else
          error_message = result.exception&.message || "Failed to create lottery"
          Rails.logger.error "Service error: #{error_message}"
          errors = [error_message]
        end

        render json: failed_json.merge(errors: errors), status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "=== LOTTERY CREATE ERROR ==="
      Rails.logger.error "Error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: e.message }, status: :internal_server_error
    end

    # GET /vzekc_verlosung/lotteries/:topic_id/packets
    #
    # Returns list of lottery packets for a topic with ticket counts
    #
    # @param topic_id [Integer] Topic ID containing the lottery packets
    #
    # @return [JSON] Array of packets with id, title, ticket_count
    def packets
      topic = Topic.find_by(id: params[:topic_id])
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = Lottery.find_by(topic_id: topic.id)
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      # Get lottery packets with eager loading
      lottery_packets =
        lottery
          .lottery_packets
          .includes(:post, lottery_packet_winners: :winner, lottery_tickets: :user)
          .order("posts.post_number")

      packets =
        lottery_packets.map do |packet|
          # Get tickets and users for this packet
          tickets = packet.lottery_tickets
          ticket_count = tickets.count

          users =
            tickets.map do |ticket|
              {
                id: ticket.user.id,
                username: ticket.user.username,
                name: ticket.user.name,
                avatar_template: ticket.user.avatar_template,
              }
            end

          # Get winners from junction table
          winners =
            packet.lottery_packet_winners.ordered.map do |lpw|
              winner_data = {
                instance_number: lpw.instance_number,
                id: lpw.winner.id,
                username: lpw.winner.username,
                name: lpw.winner.name,
                avatar_template: lpw.winner.avatar_template,
                erhaltungsbericht_topic_id: lpw.erhaltungsbericht_topic_id,
                fulfillment_state: lpw.fulfillment_state,
              }

              # Only include collected_at for lottery owner
              if topic.user_id == current_user&.id
                winner_data[:collected_at] = lpw.collected_at if lpw.collected_at
              end

              winner_data
            end

          {
            post_id: packet.post_id,
            post_number: packet.post.post_number,
            title: packet.title,
            quantity: packet.quantity,
            ticket_count: ticket_count,
            winners: winners,
            users: users,
            ordinal: packet.ordinal,
            abholerpaket: packet.abholerpaket,
            erhaltungsbericht_required: packet.erhaltungsbericht_required,
            price_cents: packet.price_cents,
            price_reason: packet.price_reason,
            state: packet.state,
          }
        end

      render json: { packets: packets }
    end

    # PUT /vzekc_verlosung/lotteries/:topic_id/end-early
    #
    # TESTING ONLY: Ends an active lottery early by setting the end time to now
    #
    # @param topic_id [Integer] Topic ID to end early
    #
    # @return [JSON] Success or error
    def end_early
      topic = Topic.find_by(id: params[:topic_id])
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = Lottery.find_by(topic_id: topic.id)
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      # Check if user can end early (must be topic owner)
      unless topic.user_id == current_user.id
        return(
          render_json_error("You don't have permission to end this lottery", status: :forbidden)
        )
      end

      # Check if it's actually active
      unless lottery.active?
        return render_json_error("This lottery is not active", status: :unprocessable_entity)
      end

      # Set end time to now so lottery becomes drawable
      lottery.update!(ends_at: Time.zone.now)

      # Cancel the previously scheduled end notification and fire immediately
      Jobs.cancel_scheduled_job(:vzekc_verlosung_notify_lottery_ended, lottery_id: lottery.id)
      Jobs.enqueue(:vzekc_verlosung_notify_lottery_ended, lottery_id: lottery.id)

      head :no_content
    end

    # GET /vzekc_verlosung/lotteries/:topic_id/drawing-data
    #
    # Returns data needed for lottery drawing in the format expected by lottery.js
    #
    # @param topic_id [Integer] Topic ID to get drawing data for
    #
    # @return [JSON] Drawing data including title, timestamp, packets with participants
    def drawing_data
      topic = Topic.find_by(id: params[:topic_id])
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = Lottery.find_by(topic_id: topic.id)
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      # Check if user can draw (must be topic owner)
      unless topic.user_id == current_user.id
        return(
          render_json_error("You don't have permission to draw this lottery", status: :forbidden)
        )
      end

      # Check if lottery has ended and not already drawn
      if lottery.active? && lottery.ends_at && lottery.ends_at > Time.zone.now
        return render_json_error("Lottery has not ended yet", status: :unprocessable_entity)
      end

      if lottery.results.present?
        return render_json_error("Lottery has already been drawn", status: :unprocessable_entity)
      end

      # Get all lottery packets with tickets (excluding Abholerpaket which is already assigned)
      lottery_packets =
        lottery
          .lottery_packets
          .where(abholerpaket: false)
          .joins(:post)
          .includes(lottery_tickets: :user)
          .order("posts.post_number")

      # Build packets array in the format expected by lottery.js
      packets =
        lottery_packets.map do |packet|
          # Get all tickets for this packet
          tickets = packet.lottery_tickets

          # Group by user and count tickets
          participants =
            tickets
              .group_by(&:user)
              .map do |user, user_tickets|
                { id: user.id, name: user.username, tickets: user_tickets.count }
              end

          {
            id: packet.post_id,
            title: packet.title,
            participants: participants,
            quantity: packet.quantity,
          }
        end

      # The timestamp should be when the lottery was published (went active)
      # Use ends_at minus duration as published_at
      duration_days = lottery.duration_days || 14
      published_at = lottery.ends_at ? lottery.ends_at - duration_days.days : topic.created_at

      render json: {
               title: topic.title,
               timestamp: published_at.iso8601,
               packets: packets,
               drawing_mode: lottery.drawing_mode,
             }
    end

    # POST /vzekc_verlosung/lotteries/:topic_id/draw
    #
    # Stores the drawing results and updates lottery state to finished
    #
    # @param topic_id [Integer] Topic ID
    # @param results [Hash] The results from lottery.js draw() method
    #
    # @return [JSON] Success or error
    def draw
      topic = Topic.find_by(id: params[:topic_id])
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = Lottery.find_by(topic_id: topic.id)
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      # Check if user can draw (must be topic owner)
      unless topic.user_id == current_user.id
        return(
          render_json_error("You don't have permission to draw this lottery", status: :forbidden)
        )
      end

      # Check if already drawn
      if lottery.results.present?
        return render_json_error("Lottery has already been drawn", status: :unprocessable_entity)
      end

      client_results = params.require(:results).permit!.to_h

      # Verify results by re-running drawing server-side
      begin
        drawing_data = DrawLottery.drawing_data(lottery)
        server_results = VzekcVerlosung::JavascriptLotteryDrawer.draw(drawing_data)

        # Compare client and server results
        unless results_match?(client_results, server_results)
          Rails.logger.warn(
            "Lottery drawing verification failed for topic #{topic.id}. " \
              "Client and server results do not match.",
          )
          return(
            render_json_error(
              "Lottery results verification failed. Please try drawing again.",
              status: :unprocessable_entity,
            )
          )
        end
      rescue MiniRacer::ScriptTerminatedError => e
        Rails.logger.error("Lottery drawing timed out for topic #{topic.id}: #{e.message}")
        return(
          render_json_error(
            "Lottery drawing timed out. Please try again.",
            status: :unprocessable_entity,
          )
        )
      rescue MiniRacer::V8OutOfMemoryError => e
        Rails.logger.error("Lottery drawing out of memory for topic #{topic.id}: #{e.message}")
        return(
          render_json_error(
            "Lottery drawing failed due to memory limit. Please contact support.",
            status: :unprocessable_entity,
          )
        )
      rescue MiniRacer::Error, StandardError => e
        Rails.logger.error("Lottery drawing error for topic #{topic.id}: #{e.message}")
        return(
          render_json_error("Lottery drawing failed: #{e.message}", status: :unprocessable_entity)
        )
      end

      # The server results are the source of truth
      begin
        DrawLottery.apply_results!(lottery, server_results)
      rescue DrawLottery::AlreadyDrawnError
        return render_json_error("Lottery has already been drawn", status: :unprocessable_entity)
      end

      head :no_content
    end

    # POST /vzekc_verlosung/lotteries/:topic_id/draw-manual
    #
    # Performs manual drawing by accepting user-selected winners for each packet
    #
    # @param topic_id [Integer] Topic ID
    # @param selections [Hash] Hash of post_id => winner_user_id
    #
    # @return [JSON] Success or error
    def draw_manual
      topic = Topic.find_by(id: params[:topic_id])
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = Lottery.find_by(topic_id: topic.id)
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      # Check if user can draw (must be topic owner)
      unless topic.user_id == current_user.id
        return(
          render_json_error("You don't have permission to draw this lottery", status: :forbidden)
        )
      end

      # Check if lottery is manual mode
      unless lottery.manual_drawing?
        return(
          render_json_error(
            "This lottery is set to automatic drawing mode",
            status: :unprocessable_entity,
          )
        )
      end

      # Check if already drawn
      if lottery.results.present?
        return render_json_error("Lottery has already been drawn", status: :unprocessable_entity)
      end

      # Get selections from params: { post_id: [winner_user_id, ...] or winner_user_id, ... }
      selections = params[:selections]&.permit!.to_h

      # Get all non-Abholerpaket packets with their tickets
      lottery_packets =
        lottery.lottery_packets.where(abholerpaket: false).includes(lottery_tickets: :user)

      # Validate: all packets with participants must have winner(s) selected
      packets_with_participants = lottery_packets.select { |p| p.lottery_tickets.any? }

      packets_with_participants.each do |packet|
        post_id_str = packet.post_id.to_s
        unless selections.key?(post_id_str) && selections[post_id_str].present?
          return(
            render_json_error(
              "Missing winner selection for packet: #{packet.title}",
              status: :unprocessable_entity,
            )
          )
        end

        # Normalize to array format
        selected_user_ids = Array(selections[post_id_str]).map(&:to_i)

        # Calculate expected winners: min of quantity and unique participants
        unique_participants = packet.lottery_tickets.distinct.count(:user_id)
        expected_winners = [packet.quantity, unique_participants].min

        if selected_user_ids.length != expected_winners
          return(
            render_json_error(
              "Expected #{expected_winners} winner(s) for packet: #{packet.title}, got #{selected_user_ids.length}",
              status: :unprocessable_entity,
            )
          )
        end

        # Validate all winners are participants
        selected_user_ids.each do |winner_user_id|
          unless packet.lottery_tickets.exists?(user_id: winner_user_id)
            return(
              render_json_error(
                "Selected winner is not a participant in packet: #{packet.title}",
                status: :unprocessable_entity,
              )
            )
          end
        end

        # Validate no duplicate winners
        if selected_user_ids.uniq.length != selected_user_ids.length
          return(
            render_json_error(
              "Duplicate winner selected for packet: #{packet.title}",
              status: :unprocessable_entity,
            )
          )
        end
      end

      # All validations passed - build the results in the same shape as lottery.js
      drawings = []
      packets_data = []

      packets_with_participants.each do |packet|
        winner_usernames =
          Array(selections[packet.post_id.to_s]).map { |id| User.find(id.to_i).username }

        drawings << {
          "text" => packet.title,
          "quantity" => packet.quantity,
          "winners" => winner_usernames,
        }
        packets_data << { "id" => packet.post_id, "title" => packet.title }
      end

      results = {
        "manual" => true,
        "drawings" => drawings,
        "packets" => packets_data,
        "drawn_at" => Time.zone.now.iso8601,
      }

      begin
        DrawLottery.apply_results!(lottery, results)
      rescue DrawLottery::AlreadyDrawnError
        return render_json_error("Lottery has already been drawn", status: :unprocessable_entity)
      end

      head :no_content
    end

    # GET /vzekc_verlosung/lotteries/:topic_id/results.json
    #
    # Downloads the lottery results as a JSON file for verification
    #
    # @param topic_id [Integer] Topic ID
    #
    # @return [JSON] The lottery results with all drawing data
    def results
      topic = Topic.find_by(id: params[:topic_id])
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = Lottery.find_by(topic_id: topic.id)
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      unless lottery.results
        return render_json_error("Lottery has not been drawn yet", status: :not_found)
      end

      # Set headers for file download
      response.headers[
        "Content-Disposition"
      ] = "attachment; filename=\"lottery-#{topic.id}-results.json\""

      render json: lottery.results
    end

    # PUT /vzekc_verlosung/lotteries/:topic_id/silence-reminders
    #
    # Silences owner reminders for a drawn lottery
    #
    # @param topic_id [Integer] Topic ID
    #
    # @return [JSON] Success or error
    def silence_reminders
      topic = Topic.find_by(id: params[:topic_id])
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = Lottery.find_by(topic_id: topic.id)
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      unless topic.user_id == current_user.id
        return(
          render_json_error(
            I18n.t("js.vzekc_verlosung.silence_reminders.error_not_owner"),
            status: :forbidden,
          )
        )
      end

      unless lottery.drawn?
        return(render_json_error("Lottery has not been drawn yet", status: :unprocessable_entity))
      end

      lottery.update!(owner_reminders_silenced: true)

      render json: success_json
    end

    # POST /vzekc_verlosung/lotteries/:topic_id/reset
    #
    # Relists a finished lottery that ended without any participants.
    # The lottery is returned to "active" state with a fresh deadline so the
    # owner can try again without creating a whole new topic.
    #
    # @param topic_id [Integer] Topic ID
    # @param duration_days [Integer] New duration in days (7-28); defaults to the
    #   lottery's previous duration_days
    #
    # @return [JSON] Success with new ends_at, or error
    def reset_lottery
      topic = Topic.find_by(id: params[:topic_id])
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = Lottery.find_by(topic_id: topic.id)
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      unless guardian.can_reset_lottery?(topic, lottery)
        return(render_json_error("This lottery cannot be relisted", status: :forbidden))
      end

      new_duration_days = (params[:duration_days] || lottery.duration_days || 14).to_i
      unless new_duration_days.between?(7, 28)
        return(
          render_json_error("Duration must be between 7 and 28 days", status: :unprocessable_entity)
        )
      end

      new_ends_at = lottery.reset_to_active!(new_duration_days)

      Jobs.cancel_scheduled_job(:vzekc_verlosung_notify_lottery_ended, lottery_id: lottery.id)
      Jobs.enqueue_at(new_ends_at, :vzekc_verlosung_notify_lottery_ended, lottery_id: lottery.id)

      render json: success_json.merge(ends_at: new_ends_at.iso8601)
    end

    private

    def create_params
      params.permit(
        :title,
        :raw,
        :duration_days,
        :category_id,
        :packet_mode,
        :single_packet_erhaltungsbericht_required,
        :has_abholerpaket,
        :abholerpaket_title,
        :abholerpaket_erhaltungsbericht_required,
        :drawing_mode,
        :auto_draw,
        :donation_id,
        packets: %i[
          title
          raw
          erhaltungsbericht_required
          ordinal
          is_abholerpaket
          quantity
          price_cents
          price_reason
        ],
      )
    end

    def serialize_topic(topic)
      { id: topic.id, title: topic.title, url: topic.url, slug: topic.slug }
    end

    # Compares client results with server results
    # Results match if they have the same RNG seed and same winners
    def results_match?(client_results, server_results)
      return false unless client_results.is_a?(Hash) && server_results.is_a?(Hash)

      # Check RNG seed matches
      return false unless client_results["rngSeed"] == server_results["rngSeed"]

      # Check drawings match
      client_drawings = client_results["drawings"] || []
      server_drawings = server_results["drawings"] || []

      return false unless client_drawings.length == server_drawings.length

      # Compare each drawing
      client_drawings.each_with_index do |client_drawing, index|
        server_drawing = server_drawings[index]
        return false unless client_drawing["text"] == server_drawing["text"]

        # Compare winners arrays
        client_winners = client_drawing["winners"] || []
        server_winners = server_drawing["winners"] || []

        return false unless client_winners == server_winners
      end

      true
    end
  end
end
