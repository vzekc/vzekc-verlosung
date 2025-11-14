# frozen_string_literal: true

module VzekcVerlosung
  # Controller for handling lottery creation
  class LotteriesController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in

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
          .includes(:post, :winner, lottery_tickets: :user)
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

          # Get winner user object if winner exists
          winner_obj = nil
          if packet.winner
            winner_obj = {
              id: packet.winner.id,
              username: packet.winner.username,
              name: packet.winner.name,
              avatar_template: packet.winner.avatar_template,
            }
          end

          packet_data = {
            post_id: packet.post_id,
            post_number: packet.post.post_number,
            title: packet.title,
            ticket_count: ticket_count,
            winner: winner_obj,
            users: users,
          }

          # Only include collected_at for lottery owner or staff
          if guardian.is_staff? || topic.user_id == current_user&.id
            packet_data[:collected_at] = packet.collected_at if packet.collected_at
          end

          packet_data
        end

      render json: { packets: packets }
    end

    # PUT /vzekc_verlosung/lotteries/:topic_id/publish
    #
    # Publishes a lottery draft topic, making it visible to all users
    # Sets the lottery to active state and schedules it to end based on duration_days
    #
    # @param topic_id [Integer] Topic ID to publish
    #
    # @return [JSON] Success or error
    def publish
      topic = Topic.find_by(id: params[:topic_id])
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = Lottery.find_by(topic_id: topic.id)
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      # Check if user can publish (must be topic owner or staff)
      unless guardian.is_staff? || topic.user_id == current_user.id
        return(
          render_json_error("You don't have permission to publish this lottery", status: :forbidden)
        )
      end

      # Check if it's actually a draft
      unless lottery.draft?
        return(
          render_json_error("This lottery is not in draft state", status: :unprocessable_entity)
        )
      end

      # Get duration (default to 14 days if not set)
      duration_days = lottery.duration_days || 14

      # Activate lottery and set end time based on duration
      lottery.publish!(duration_days.days.from_now)

      # Notify all users who have tickets in this lottery
      notify_lottery_published(topic)

      head :no_content
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

      # Check if user can end early (must be topic owner or staff)
      unless guardian.is_staff? || topic.user_id == current_user.id
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

      # Check if user can draw (must be topic owner or staff)
      unless guardian.is_staff? || topic.user_id == current_user.id
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
              .map { |user, user_tickets| { name: user.username, tickets: user_tickets.count } }

          { id: packet.post_id, title: packet.title, participants: participants }
        end

      # The timestamp should be when the lottery was published (went active)
      # Use ends_at minus duration as published_at
      duration_days = lottery.duration_days || 14
      published_at = lottery.ends_at ? lottery.ends_at - duration_days.days : topic.created_at

      render json: { title: topic.title, timestamp: published_at.iso8601, packets: packets }
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

      # Check if user can draw (must be topic owner or staff)
      unless guardian.is_staff? || topic.user_id == current_user.id
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
        drawing_data = fetch_drawing_data_for_verification(lottery)
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

      # Store verified results
      results = server_results # Use server results as source of truth
      drawn_at = Time.zone.now

      # Update lottery state
      lottery.finish!
      lottery.mark_drawn!(results)

      # Store winner on each packet
      results["drawings"].each do |drawing|
        # Find the packet by title
        packet = lottery.lottery_packets.find { |p| p.title == drawing["text"] }

        if packet && drawing["winner"].present?
          # Find winner user
          winner_user = User.find_by(username: drawing["winner"])
          packet.mark_winner!(winner_user, drawn_at) if winner_user
        end
      end

      # Notify all participants that winners have been drawn
      notify_lottery_drawn(topic)

      # Send special notification to winners
      notify_winners(topic, results)

      # Send notification to participants who didn't win anything
      notify_non_winners(topic, results)

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

    private

    def create_params
      params.permit(
        :title,
        :duration_days,
        :category_id,
        :has_abholerpaket,
        :abholerpaket_title,
        packets: %i[title erhaltungsbericht_required],
      )
    end

    def serialize_topic(topic)
      { id: topic.id, title: topic.title, url: topic.url, slug: topic.slug }
    end

    # Fetches drawing data in the format expected by lottery.js
    # This is similar to drawing_data endpoint but doesn't require permissions
    def fetch_drawing_data_for_verification(lottery)
      topic = lottery.topic

      # Get all lottery packets with tickets
      lottery_packets =
        lottery
          .lottery_packets
          .joins(:post)
          .includes(lottery_tickets: :user)
          .order("posts.post_number")

      packets =
        lottery_packets.map do |packet|
          tickets = packet.lottery_tickets

          participants =
            tickets
              .group_by(&:user)
              .map { |user, user_tickets| { name: user.username, tickets: user_tickets.count } }

          { id: packet.post_id, title: packet.title, participants: participants }
        end

      # Calculate published_at from ends_at and duration
      duration_days = lottery.duration_days || 14
      published_at = lottery.ends_at ? lottery.ends_at - duration_days.days : topic.created_at

      { title: topic.title, timestamp: published_at.iso8601, packets: packets }
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
        return false unless client_drawing["winner"] == server_drawing["winner"]
      end

      true
    end

    def extract_title_from_markdown(raw)
      # Extract first heading from markdown (e.g., "# Title")
      # Match only the first line, not including any content after the newline
      match = raw.match(/^#\s+(.+)$/)
      match ? match[1].strip : nil
    end

    # Notify all users with tickets that the lottery has been published
    def notify_lottery_published(topic)
      participant_user_ids = get_lottery_participant_user_ids(topic)

      participant_user_ids.each do |user_id|
        user = User.find_by(id: user_id)
        next unless user

        Notification.consolidate_or_create!(
          notification_type: Notification.types[:vzekc_verlosung_published],
          user_id: user.id,
          topic_id: topic.id,
          post_number: 1,
          data: {
            topic_title: topic.title,
            message: "vzekc_verlosung.notifications.lottery_published",
          }.to_json,
        )
      end
    end

    # Notify all users with tickets that winners have been drawn
    def notify_lottery_drawn(topic)
      participant_user_ids = get_lottery_participant_user_ids(topic)

      participant_user_ids.each do |user_id|
        user = User.find_by(id: user_id)
        next unless user

        begin
          Notification.consolidate_or_create!(
            notification_type: Notification.types[:vzekc_verlosung_drawn],
            user_id: user.id,
            topic_id: topic.id,
            post_number: 1,
            data: {
              topic_title: topic.title,
              message: "vzekc_verlosung.notifications.lottery_drawn",
            }.to_json,
          )
        rescue => e
          Rails.logger.error(
            "Failed to create lottery_drawn notification for user #{user_id} (#{user.username}) " \
              "on topic #{topic.id}: #{e.class}: #{e.message}",
          )
        end
      end
    end

    # Notify winners that they won a packet
    def notify_winners(topic, results)
      lottery = Lottery.find_by(topic_id: topic.id)
      return unless lottery

      # Group drawings by winner to send one message per winner with all packets won
      winners_packets = Hash.new { |h, k| h[k] = [] }

      results["drawings"].each do |drawing|
        winner_username = drawing["winner"]
        packet_title = drawing["text"]
        next unless winner_username

        winner_user = User.find_by(username: winner_username)
        next unless winner_user

        # Find the packet by title
        lottery_packet = lottery.lottery_packets.find { |p| p.title == packet_title }
        next unless lottery_packet

        packet_post = lottery_packet.post
        post_number = packet_post ? packet_post.post_number : 1

        # Create in-app notification
        begin
          Notification.consolidate_or_create!(
            notification_type: Notification.types[:vzekc_verlosung_won],
            user_id: winner_user.id,
            topic_id: topic.id,
            post_number: post_number,
            data: {
              packet_title: packet_title,
              message: "vzekc_verlosung.notifications.lottery_won",
            }.to_json,
          )
        rescue => e
          Rails.logger.error(
            "Failed to create winner notification for user #{winner_user.id} (#{winner_user.username}) " \
              "on topic #{topic.id}, packet '#{packet_title}': #{e.class}: #{e.message}",
          )
        end

        # Collect packet info for PM
        winners_packets[winner_user] << {
          title: packet_title,
          post_number: post_number,
          post: packet_post,
        }
      end

      # Send personal message to each winner with all their packets
      winners_packets.each do |winner_user, packets|
        begin
          send_winner_personal_message(topic, winner_user, packets)
        rescue => e
          Rails.logger.error(
            "Failed to send winner PM for topic #{topic.id} to user #{winner_user.username}: " \
              "#{e.class}: #{e.message}",
          )
        end
      end
    end

    # Notify participants who didn't win anything
    def notify_non_winners(topic, results)
      # Get all winner usernames
      winner_usernames = results["drawings"].map { |drawing| drawing["winner"] }.compact

      # Get all participants
      participant_user_ids = get_lottery_participant_user_ids(topic)

      # Notify participants who are not winners
      participant_user_ids.each do |user_id|
        user = User.find_by(id: user_id)
        next unless user
        next if winner_usernames.include?(user.username)

        begin
          Notification.consolidate_or_create!(
            notification_type: Notification.types[:vzekc_verlosung_did_not_win],
            user_id: user.id,
            topic_id: topic.id,
            post_number: 1,
            data: {
              topic_title: topic.title,
              message: "vzekc_verlosung.notifications.did_not_win",
            }.to_json,
          )
        rescue => e
          Rails.logger.error(
            "Failed to create non-winner notification for user #{user_id} (#{user.username}) " \
              "on topic #{topic.id}: #{e.class}: #{e.message}",
          )
        end
      end
    end

    # Get all unique user IDs who have tickets in this lottery
    def get_lottery_participant_user_ids(topic)
      VzekcVerlosung::LotteryTicket
        .joins(:post)
        .where(posts: { topic_id: topic.id })
        .distinct
        .pluck(:user_id)
    end

    # Send a personal message to a winner with details about their prize(s)
    def send_winner_personal_message(topic, winner_user, packets)
      lottery_creator = topic.user

      # Get the main post content (excluding images)
      main_post = topic.posts.first
      main_post_content = strip_images_from_markdown(main_post.raw)

      # Build packet list with links
      packet_list =
        packets
          .map do |packet|
            packet_url = "#{Discourse.base_url}#{topic.relative_url}/#{packet[:post_number]}"
            "- [#{packet[:title]}](#{packet_url})"
          end
          .join("\n")

      # Build the message in the winner's locale
      message_title =
        I18n.with_locale(winner_user.effective_locale) do
          I18n.t("vzekc_verlosung.winner_message.title", topic_title: topic.title)
        end

      message_body =
        I18n.with_locale(winner_user.effective_locale) do
          I18n.t(
            "vzekc_verlosung.winner_message.body",
            username: winner_user.username,
            topic_title: topic.title,
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
            packet_list: packet_list,
            main_post_content: main_post_content,
          )
        end

      # Create the personal message
      PostCreator.create!(
        lottery_creator,
        title: message_title,
        raw: message_body,
        archetype: Archetype.private_message,
        target_usernames: winner_user.username,
        skip_validations: true,
      )
    rescue => e
      Rails.logger.error(
        "Failed to send winner PM for topic #{topic.id} to user #{winner_user.username}: #{e.message}",
      )
    end

    # Strip image markdown and HTML from content
    def strip_images_from_markdown(content)
      # Remove markdown images: ![alt](url)
      content = content.gsub(/!\[.*?\]\(.*?\)/, "")

      # Remove HTML img tags
      content = content.gsub(/<img[^>]*>/, "")

      # Remove standalone image URLs that might be on their own line
      content = content.gsub(%r{^\s*https?://\S+\.(jpg|jpeg|png|gif|webp)\s*$}i, "")

      content.strip
    end
  end
end
