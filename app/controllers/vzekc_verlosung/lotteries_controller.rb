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
    # @param description [String] Description for the main topic
    # @param category_id [Integer] Category ID where topics should be created
    # @param packets [Array<Hash>] Array of packet data with title, description
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

      # Get all posts in the topic, ordered by post_number
      all_posts = Post
        .where(topic_id: topic.id)
        .order(:post_number)

      # Filter to only lottery packet posts using custom fields
      packet_posts = all_posts.select do |post|
        post.custom_fields["is_lottery_packet"] == true
      end

      packets = packet_posts.map do |post|
        # Extract title from markdown (first heading)
        title = extract_title_from_markdown(post.raw) || "Packet ##{post.post_number}"

        # Get ticket count for this packet
        ticket_count = VzekcVerlosung::LotteryTicket.where(post_id: post.id).count

        {
          post_id: post.id,
          post_number: post.post_number,
          title: title,
          ticket_count: ticket_count
        }
      end

      render json: { packets: packets }
    end

    # PUT /vzekc_verlosung/lotteries/:topic_id/publish
    #
    # Publishes a lottery draft topic, making it visible to all users
    # Sets the lottery to active state and schedules it to end in 2 weeks
    #
    # @param topic_id [Integer] Topic ID to publish
    #
    # @return [JSON] Success or error
    def publish
      topic = Topic.find_by(id: params[:topic_id])
      return render_json_error("Topic not found", status: :not_found) unless topic

      # Check if user can publish (must be topic owner or staff)
      unless guardian.is_staff? || topic.user_id == current_user.id
        return render_json_error("You don't have permission to publish this lottery", status: :forbidden)
      end

      # Check if it's actually a draft
      unless topic.custom_fields["lottery_state"] == "draft"
        return render_json_error("This lottery is not in draft state", status: :unprocessable_entity)
      end

      # Activate lottery and set end time to 2 weeks from now
      topic.custom_fields["lottery_state"] = "active"
      topic.custom_fields["lottery_ends_at"] = 2.weeks.from_now
      topic.save_custom_fields

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

      # Check if user can draw (must be topic owner or staff)
      unless guardian.is_staff? || topic.user_id == current_user.id
        return render_json_error("You don't have permission to draw this lottery", status: :forbidden)
      end

      # Check if lottery has ended and not already drawn
      if topic.custom_fields["lottery_state"] == "active" && topic.lottery_ends_at && topic.lottery_ends_at > Time.zone.now
        return render_json_error("Lottery has not ended yet", status: :unprocessable_entity)
      end

      if topic.custom_fields["lottery_results"].present?
        return render_json_error("Lottery has already been drawn", status: :unprocessable_entity)
      end

      # Get all packet posts
      packet_posts = Post
        .where(topic_id: topic.id)
        .order(:post_number)
        .select { |post| post.custom_fields["is_lottery_packet"] == true }

      # Build packets array in the format expected by lottery.js
      packets = packet_posts.map do |post|
        title = extract_title_from_markdown(post.raw) || "Packet ##{post.post_number}"

        # Get all tickets for this packet
        tickets = VzekcVerlosung::LotteryTicket.where(post_id: post.id).includes(:user)

        # Group by user and count tickets
        participants = tickets.group_by(&:user).map do |user, user_tickets|
          {
            name: user.username,
            tickets: user_tickets.count
          }
        end

        {
          id: post.id,
          title: title,
          participants: participants
        }
      end

      # The timestamp should be when the lottery was published (went active)
      # For now, we'll use when lottery_ends_at was set minus 2 weeks
      published_at = topic.lottery_ends_at ? topic.lottery_ends_at - 2.weeks : topic.created_at

      render json: {
        title: topic.title,
        timestamp: published_at.iso8601,
        packets: packets
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

      # Check if user can draw (must be topic owner or staff)
      unless guardian.is_staff? || topic.user_id == current_user.id
        return render_json_error("You don't have permission to draw this lottery", status: :forbidden)
      end

      # Check if already drawn
      if topic.custom_fields["lottery_results"].present?
        return render_json_error("Lottery has already been drawn", status: :unprocessable_entity)
      end

      results = params.require(:results).permit!.to_h

      # Store results on topic
      topic.custom_fields["lottery_results"] = results
      topic.custom_fields["lottery_drawn_at"] = Time.zone.now
      topic.custom_fields["lottery_state"] = "finished"
      topic.save_custom_fields

      # Store winner on each packet post
      results["drawings"].each do |drawing|
        # Find the packet post by title
        packet_post = Post
          .where(topic_id: topic.id)
          .find do |post|
            post.custom_fields["is_lottery_packet"] == true &&
            extract_title_from_markdown(post.raw) == drawing["text"]
          end

        if packet_post
          packet_post.custom_fields["lottery_winner"] = drawing["winner"]
          packet_post.save_custom_fields
        end
      end

      head :no_content
    end

    private

    def create_params
      params.permit(:title, :description, :category_id, packets: [:title, :description])
    end

    def serialize_topic(topic)
      {
        id: topic.id,
        title: topic.title,
        url: topic.url,
        slug: topic.slug,
      }
    end

    def extract_title_from_markdown(raw)
      # Extract first heading from markdown (e.g., "# Title")
      # Match only the first line, not including any content after the newline
      match = raw.match(/^#\s+(.+)$/)
      match ? match[1].strip : nil
    end
  end
end
