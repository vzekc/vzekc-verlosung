# frozen_string_literal: true

module VzekcVerlosung
  # Controller for handling lottery ticket purchases and returns
  class TicketsController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in

    # POST /vzekc_verlosung/tickets
    # Creates a lottery ticket for the current user and post
    def create
      post = Post.find_by(id: params[:post_id])
      return render_json_error("Post not found", status: :not_found) unless post

      topic = post.topic

      # Check if lottery is active (not draft, not finished)
      unless topic.lottery_active?
        return render_json_error("Lottery is not active", status: :unprocessable_entity)
      end

      # Check if lottery has ended
      if topic.lottery_ends_at && topic.lottery_ends_at <= Time.zone.now
        return render_json_error("Lottery has ended", status: :unprocessable_entity)
      end

      ticket = VzekcVerlosung::LotteryTicket.new(post_id: post.id, user_id: current_user.id)

      if ticket.save
        # Auto-watch the lottery topic so user gets notifications for updates
        TopicUser.change(
          current_user.id,
          topic.id,
          notification_level: TopicUser.notification_levels[:watching],
          notifications_reason_id: TopicUser.notification_reasons[:user_interacted],
        )

        # Notify the lottery creator that a ticket was bought
        notify_ticket_bought(topic, post, current_user)

        render json: success_json.merge(ticket_packet_status_response(post.id))
      else
        render json: failed_json.merge(errors: ticket.errors.full_messages),
               status: :unprocessable_entity
      end
    end

    # DELETE /vzekc_verlosung/tickets/:post_id
    # Removes the lottery ticket for the current user and post
    def destroy
      ticket =
        VzekcVerlosung::LotteryTicket.find_by(post_id: params[:post_id], user_id: current_user.id)
      return render_json_error("Ticket not found", status: :not_found) unless ticket

      post = Post.find_by(id: params[:post_id])
      if post
        topic = post.topic

        # Check if lottery is active (not draft, not finished)
        unless topic.lottery_active?
          return render_json_error("Lottery is not active", status: :unprocessable_entity)
        end

        # Check if lottery has ended
        if topic.lottery_ends_at && topic.lottery_ends_at <= Time.zone.now
          return render_json_error("Lottery has ended", status: :unprocessable_entity)
        end
      end

      ticket.destroy

      # Notify the lottery creator that a ticket was returned
      notify_ticket_returned(post.topic, post, current_user) if post

      render json: success_json.merge(ticket_packet_status_response(params[:post_id]))
    end

    # GET /vzekc_verlosung/tickets/packet-status/:post_id
    # Returns whether the current user has a ticket for a lottery packet post, total count, and list of users
    def packet_status
      render json: ticket_packet_status_response(params[:post_id])
    end

    # POST /vzekc_verlosung/packets/:post_id/mark-collected
    #
    # Marks a packet as collected by the winner
    #
    # @param post_id [Integer] Post ID of the packet
    #
    # @return [JSON] Updated packet status
    def mark_collected
      post = Post.find_by(id: params[:post_id])
      return render_json_error("Post not found", status: :not_found) unless post

      # Verify it's a lottery packet
      unless post.custom_fields["is_lottery_packet"] == true
        return render_json_error("Not a lottery packet", status: :bad_request)
      end

      topic = post.topic
      return render_json_error("Topic not found", status: :not_found) unless topic

      # Check permissions - only lottery owner or staff
      unless guardian.can_manage_lottery_packets?(topic)
        return(
          render_json_error("You don't have permission to manage this lottery", status: :forbidden)
        )
      end

      # Check if lottery is finished and drawn
      unless topic.lottery_finished? && topic.lottery_drawn?
        return(
          render_json_error(
            "Lottery must be finished and drawn before marking packets as collected",
            status: :unprocessable_entity,
          )
        )
      end

      # Check if there's a winner
      winner_username = post.custom_fields["lottery_winner"]
      if winner_username.blank?
        return(render_json_error("No winner for this packet", status: :unprocessable_entity))
      end

      # Check if already collected
      if post.custom_fields["packet_collected_at"].present?
        return(
          render_json_error("Packet already marked as collected", status: :unprocessable_entity)
        )
      end

      # Mark as collected
      post.custom_fields["packet_collected_at"] = Time.zone.now
      post.save_custom_fields

      # Return updated packet status
      render json: ticket_packet_status_response(post, current_user)
    end

    # POST /vzekc_verlosung/packets/:post_id/create-erhaltungsbericht
    #
    # Creates an Erhaltungsbericht topic for a collected packet
    #
    # @param post_id [Integer] Post ID of the packet
    #
    # @return [JSON] Created topic URL
    def create_erhaltungsbericht
      post = Post.find_by(id: params[:post_id])
      return render_json_error("Post not found", status: :not_found) unless post

      # Verify it's a lottery packet
      unless post.custom_fields["is_lottery_packet"] == true
        return render_json_error("Not a lottery packet", status: :bad_request)
      end

      # Check if packet was collected
      if post.custom_fields["packet_collected_at"].blank?
        return(
          render_json_error("Packet not yet marked as collected", status: :unprocessable_entity)
        )
      end

      # Check if user is the winner
      winner_username = post.custom_fields["lottery_winner"]
      unless winner_username == current_user.username
        return(
          render_json_error("Only the winner can create an Erhaltungsbericht", status: :forbidden)
        )
      end

      # Check if Erhaltungsbericht already exists (and still exists)
      erhaltungsbericht_topic_id = post.custom_fields["erhaltungsbericht_topic_id"]
      if erhaltungsbericht_topic_id.present?
        if Topic.exists?(id: erhaltungsbericht_topic_id)
          return(
            render_json_error("Erhaltungsbericht already created", status: :unprocessable_entity)
          )
        else
          # Topic was deleted, clear the field to allow creating a new one
          post.custom_fields.delete("erhaltungsbericht_topic_id")
          post.save_custom_fields
        end
      end

      # Get category for Erhaltungsberichte
      category_id = SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id
      unless category_id.present? && Category.exists?(id: category_id)
        return(
          render_json_error(
            "Erhaltungsberichte category not configured",
            status: :unprocessable_entity,
          )
        )
      end

      # Extract packet title
      packet_title = extract_title_from_markdown(post.raw) || "Paket ##{post.post_number}"

      # Get lottery topic title
      lottery_title = post.topic.title

      # Get template and replace placeholders
      template = SiteSetting.vzekc_verlosung_erhaltungsbericht_template
      packet_url = "#{Discourse.base_url}/t/#{post.topic.slug}/#{post.topic_id}/#{post.post_number}"
      content = template.gsub("[LOTTERY_TITLE]", lottery_title).gsub("[PACKET_LINK]", packet_url)

      # Create the topic
      begin
        topic_creator =
          PostCreator.new(
            current_user,
            title: packet_title,
            raw: content,
            category: category_id,
            skip_validations: false,
          )

        result = topic_creator.create

        if topic_creator.errors.present?
          return(
            render_json_error(
              topic_creator.errors.full_messages.join(", "),
              status: :unprocessable_entity,
            )
          )
        end

        # Store the reference
        post.custom_fields["erhaltungsbericht_topic_id"] = result.topic_id
        post.save_custom_fields

        # Also store reverse reference on the erhaltungsbericht topic
        result.topic.custom_fields["packet_post_id"] = post.id
        result.topic.custom_fields["packet_topic_id"] = post.topic_id
        result.topic.save_custom_fields

        render json: success_json.merge(topic_url: result.topic.relative_url)
      rescue => e
        render_json_error(
          "Failed to create Erhaltungsbericht: #{e.message}",
          status: :internal_server_error,
        )
      end
    end

    private

    def ticket_packet_status_response(post_or_id, user = nil)
      user ||= current_user
      post = post_or_id.is_a?(Post) ? post_or_id : Post.find_by(id: post_or_id)
      return {} unless post

      has_ticket = VzekcVerlosung::LotteryTicket.exists?(post_id: post.id, user_id: user.id)

      tickets = VzekcVerlosung::LotteryTicket.where(post_id: post.id).includes(:user)
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
      winner_username = post.custom_fields["lottery_winner"]
      winner = nil
      if winner_username.present?
        winner_user = User.find_by(username: winner_username)
        if winner_user
          winner = {
            id: winner_user.id,
            username: winner_user.username,
            name: winner_user.name,
            avatar_template: winner_user.avatar_template,
          }
        end
      end

      response = {
        has_ticket: has_ticket,
        ticket_count: ticket_count,
        users: users,
        winner: winner,
      }

      # Only include collected_at for lottery owner or staff
      topic = post.topic
      if topic && (guardian.is_staff? || topic.user_id == user.id)
        collected_at = post.custom_fields["packet_collected_at"]
        if collected_at
          response[:collected_at] = (
            if collected_at.is_a?(String)
              Time.zone.parse(collected_at)
            else
              collected_at
            end
          )
        end
      end

      response
    end

    # Notify the lottery creator that a ticket was bought
    def notify_ticket_bought(topic, post, buyer)
      return if topic.user_id == buyer.id # Don't notify if creator bought their own ticket

      packet_title = extract_title_from_markdown(post.raw) || "Packet ##{post.post_number}"

      Notification.consolidate_or_create!(
        notification_type: Notification.types[:vzekc_verlosung_ticket_bought],
        user_id: topic.user_id,
        topic_id: topic.id,
        post_number: post.post_number,
        data: { display_username: buyer.username, packet_title: packet_title }.to_json,
      )
    end

    # Notify the lottery creator that a ticket was returned
    def notify_ticket_returned(topic, post, returner)
      return if topic.user_id == returner.id # Don't notify if creator returned their own ticket

      packet_title = extract_title_from_markdown(post.raw) || "Packet ##{post.post_number}"

      Notification.consolidate_or_create!(
        notification_type: Notification.types[:vzekc_verlosung_ticket_returned],
        user_id: topic.user_id,
        topic_id: topic.id,
        post_number: post.post_number,
        data: { display_username: returner.username, packet_title: packet_title }.to_json,
      )
    end

    # Extract title from markdown (copied from lotteries_controller)
    def extract_title_from_markdown(raw)
      match = raw.match(/^#\s+(.+)$/)
      match ? match[1].strip : nil
    end
  end
end
