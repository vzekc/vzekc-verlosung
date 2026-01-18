# frozen_string_literal: true

module VzekcVerlosung
  # Controller for handling lottery ticket draws and returns
  class TicketsController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in

    # POST /vzekc_verlosung/tickets
    # Creates a lottery ticket for the current user and post
    def create
      post = Post.find_by(id: params[:post_id])
      return render_json_error("Post not found", status: :not_found) unless post

      topic = post.topic
      lottery = Lottery.find_by(topic_id: topic.id)
      return render_json_error("Not a lottery topic", status: :not_found) unless lottery

      # Check if lottery is active (not draft, not finished)
      unless lottery.active?
        return render_json_error("Lottery is not active", status: :unprocessable_entity)
      end

      # Check if lottery has ended
      if lottery.ends_at && lottery.ends_at <= Time.zone.now
        return render_json_error("Lottery has ended", status: :unprocessable_entity)
      end

      # Prevent drawing tickets for Abholerpaket (packet 0)
      packet = LotteryPacket.find_by(post_id: post.id)
      if packet&.abholerpaket?
        return(
          render_json_error(
            "Cannot draw tickets for the Abholerpaket",
            status: :unprocessable_entity,
          )
        )
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

        # Notify the lottery creator that a ticket was drawn
        begin
          notify_ticket_bought(topic, post, current_user)
        rescue => e
          Rails.logger.error "notify_ticket_bought failed: #{e.class}: #{e.message}"
        end

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
        lottery = Lottery.find_by(topic_id: topic.id)

        if lottery
          # Check if lottery is active (not draft, not finished)
          unless lottery.active?
            return render_json_error("Lottery is not active", status: :unprocessable_entity)
          end

          # Check if lottery has ended
          if lottery.ends_at && lottery.ends_at <= Time.zone.now
            return render_json_error("Lottery has ended", status: :unprocessable_entity)
          end
        end
      end

      ticket.destroy

      # Notify the lottery creator that a ticket was returned
      begin
        notify_ticket_returned(post.topic, post, current_user) if post
      rescue => e
        Rails.logger.error "notify_ticket_returned failed: #{e.class}: #{e.message}"
      end

      render json: success_json.merge(ticket_packet_status_response(params[:post_id]))
    end

    # GET /vzekc_verlosung/tickets/packet-status/:post_id
    # Returns whether the current user has a ticket for a lottery packet post, total count, and list of users
    def packet_status
      render json: ticket_packet_status_response(params[:post_id])
    end

    # POST /vzekc_verlosung/packets/:post_id/mark-collected
    #
    # Marks a packet as collected by the winner or lottery owner
    #
    # @param post_id [Integer] Post ID of the packet
    # @param instance_number [Integer] Optional instance number (for lottery owner marking specific winner)
    #
    # @return [JSON] Updated packet status
    def mark_collected
      post = Post.find_by(id: params[:post_id])
      return render_json_error("Post not found", status: :not_found) unless post

      packet =
        LotteryPacket.includes(:lottery_packet_winners).find_by(post_id: post.id)
      return render_json_error("Not a lottery packet", status: :bad_request) unless packet

      topic = post.topic
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = packet.lottery
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      # Check if lottery is finished and drawn
      unless lottery.finished? && lottery.drawn?
        return(
          render_json_error(
            "Lottery must be finished and drawn before marking packets as collected",
            status: :unprocessable_entity,
          )
        )
      end

      is_lottery_owner = topic.user_id == current_user.id

      # Find the winner entry to mark
      winner_entry =
        if params[:instance_number].present? && is_lottery_owner
          # Lottery owner can mark any specific instance
          packet.lottery_packet_winners.find { |w| w.instance_number == params[:instance_number].to_i }
        else
          # Regular winner can only mark their own entry
          packet.lottery_packet_winners.find { |w| w.winner_user_id == current_user.id }
        end

      # Check if winner entry exists
      unless winner_entry
        if is_lottery_owner && params[:instance_number].present?
          return render_json_error("Winner entry not found for instance #{params[:instance_number]}", status: :not_found)
        else
          return render_json_error("Only a winner can mark a packet as collected", status: :forbidden)
        end
      end

      # Check if already collected
      if winner_entry.collected?
        return(
          render_json_error("Packet already marked as collected", status: :unprocessable_entity)
        )
      end

      # Mark as collected
      winner_entry.mark_collected!

      # Return updated packet status
      render json: ticket_packet_status_response(post, current_user)
    end

    # POST /vzekc_verlosung/packets/:post_id/mark-shipped
    #
    # Marks a packet as shipped by the lottery owner
    # Sends a PM to the winner with optional tracking info
    #
    # @param post_id [Integer] Post ID of the packet
    # @param instance_number [Integer] Instance number of the winner entry to mark
    # @param tracking_info [String] Optional tracking information
    #
    # @return [JSON] Updated packet status
    def mark_shipped
      post = Post.find_by(id: params[:post_id])
      return render_json_error("Post not found", status: :not_found) unless post

      packet =
        LotteryPacket.includes(:lottery_packet_winners).find_by(post_id: post.id)
      return render_json_error("Not a lottery packet", status: :bad_request) unless packet

      topic = post.topic
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = packet.lottery
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      # Check if lottery is finished and drawn
      unless lottery.finished? && lottery.drawn?
        return(
          render_json_error(
            "Lottery must be finished and drawn before marking packets as shipped",
            status: :unprocessable_entity,
          )
        )
      end

      # Only lottery owner can mark as shipped
      unless topic.user_id == current_user.id
        return render_json_error("Only the lottery owner can mark packets as shipped", status: :forbidden)
      end

      # Find the winner entry by instance number
      instance_number = params[:instance_number].to_i
      winner_entry = packet.lottery_packet_winners.find { |w| w.instance_number == instance_number }

      unless winner_entry
        return render_json_error("Winner entry not found for instance #{instance_number}", status: :not_found)
      end

      # Check if already shipped
      if winner_entry.shipped?
        return(
          render_json_error("Packet already marked as shipped", status: :unprocessable_entity)
        )
      end

      tracking_info = params[:tracking_info].presence

      # Mark as shipped with tracking info
      winner_entry.mark_shipped!(Time.zone.now, tracking_info: tracking_info)

      # Send PM to winner
      send_shipped_notification_pm(
        winner: winner_entry.winner,
        sender: current_user,
        packet: packet,
        lottery_topic: topic,
        tracking_info: tracking_info,
      )

      # Return updated packet status
      render json: ticket_packet_status_response(post, current_user)
    end

    # POST /vzekc_verlosung/packets/:post_id/mark-handed-over
    #
    # Marks a packet as handed over by the lottery owner
    # This sets both shipped_at and collected_at (no need for winner to confirm)
    #
    # @param post_id [Integer] Post ID of the packet
    # @param instance_number [Integer] Instance number of the winner entry to mark
    #
    # @return [JSON] Updated packet status
    def mark_handed_over
      post = Post.find_by(id: params[:post_id])
      return render_json_error("Post not found", status: :not_found) unless post

      packet =
        LotteryPacket.includes(:lottery_packet_winners).find_by(post_id: post.id)
      return render_json_error("Not a lottery packet", status: :bad_request) unless packet

      topic = post.topic
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = packet.lottery
      return render_json_error("Lottery not found", status: :not_found) unless lottery

      # Check if lottery is finished and drawn
      unless lottery.finished? && lottery.drawn?
        return(
          render_json_error(
            "Lottery must be finished and drawn before marking packets as handed over",
            status: :unprocessable_entity,
          )
        )
      end

      # Only lottery owner can mark as handed over
      unless topic.user_id == current_user.id
        return render_json_error("Only the lottery owner can mark packets as handed over", status: :forbidden)
      end

      # Find the winner entry by instance number
      instance_number = params[:instance_number].to_i
      winner_entry = packet.lottery_packet_winners.find { |w| w.instance_number == instance_number }

      unless winner_entry
        return render_json_error("Winner entry not found for instance #{instance_number}", status: :not_found)
      end

      # Check if already collected (handed over implies collected)
      if winner_entry.collected?
        return(
          render_json_error("Packet already marked as collected", status: :unprocessable_entity)
        )
      end

      # Mark as handed over (sets both shipped_at and collected_at)
      winner_entry.mark_handed_over!

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

      # Find the lottery packet
      packet =
        LotteryPacket
          .includes(lottery_packet_winners: :erhaltungsbericht_topic)
          .find_by(post_id: post.id)
      return render_json_error("Not a lottery packet", status: :bad_request) unless packet

      # Find the current user's winner entry
      winner_entry = packet.lottery_packet_winners.find { |w| w.winner_user_id == current_user.id }

      # Check if user is a winner
      unless winner_entry
        return(
          render_json_error("Only a winner can create an Erhaltungsbericht", status: :forbidden)
        )
      end

      # Check if packet was collected by this user
      unless winner_entry.collected?
        return(
          render_json_error("Packet not yet marked as collected", status: :unprocessable_entity)
        )
      end

      # Check if Erhaltungsbericht already exists (and still exists)
      if winner_entry.erhaltungsbericht_topic_id.present?
        if winner_entry.erhaltungsbericht_topic.present?
          return(
            render_json_error("Erhaltungsbericht already created", status: :unprocessable_entity)
          )
        else
          # Topic was deleted, clear the field to allow creating a new one
          winner_entry.update!(erhaltungsbericht_topic_id: nil)
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
      packet_title =
        VzekcVerlosung::TitleExtractor.extract_title(post.raw) || "Paket ##{post.post_number}"

      # Get lottery topic title
      lottery_title = post.topic.title

      # Compose topic title: "<packet-title> aus <lottery-title>"
      topic_title = "#{packet_title} aus #{lottery_title}"

      # Get template (no placeholder replacement needed - links are stored as custom fields)
      template = SiteSetting.vzekc_verlosung_erhaltungsbericht_template

      # Create the topic
      begin
        topic_creator =
          PostCreator.new(
            current_user,
            title: topic_title,
            raw: template,
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

        # Store the reference on the winner entry
        winner_entry.link_report!(result.topic)

        # Also store reverse reference on the erhaltungsbericht topic (for backward compatibility)
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

    # PUT /vzekc_verlosung/packets/:post_id/toggle-notifications
    #
    # Toggles the notifications_silenced flag for a lottery packet
    # Only available after the lottery has been drawn and only for the lottery owner
    #
    # @param post_id [Integer] Post ID of the packet
    #
    # @return [JSON] Updated notifications_silenced status
    def toggle_notifications
      post = Post.find_by(id: params[:post_id])
      return render_json_error("Post not found", status: :not_found) unless post

      packet = LotteryPacket.find_by(post_id: post.id)
      return render_json_error("Not a lottery packet", status: :bad_request) unless packet

      topic = post.topic
      return render_json_error("Topic not found", status: :not_found) unless topic

      lottery = Lottery.find_by(topic_id: topic.id)
      if lottery&.drawn_at.blank?
        return render_json_error("Lottery has not been drawn yet", status: :bad_request)
      end

      unless topic.user_id == current_user.id
        return(
          render_json_error(
            "Only the lottery owner can toggle packet notifications",
            status: :forbidden,
          )
        )
      end

      packet.update!(notifications_silenced: !packet.notifications_silenced)
      render json: success_json.merge(notifications_silenced: packet.notifications_silenced)
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

      # Get packet with winners
      packet =
        LotteryPacket
          .includes(lottery_packet_winners: %i[winner erhaltungsbericht_topic])
          .find_by(post_id: post.id)

      topic = post.topic

      # Build winners array
      winners =
        packet&.lottery_packet_winners&.ordered&.map do |lpw|
          winner_data = {
            instance_number: lpw.instance_number,
            id: lpw.winner.id,
            username: lpw.winner.username,
            name: lpw.winner.name,
            avatar_template: lpw.winner.avatar_template,
          }

          # Include erhaltungsbericht_topic_id if exists
          if lpw.erhaltungsbericht_topic_id && lpw.erhaltungsbericht_topic
            winner_data[:erhaltungsbericht_topic_id] = lpw.erhaltungsbericht_topic_id
          end

          # Include shipped_at and collected_at for lottery owner or this winner
          is_this_winner = user && user.id == lpw.winner_user_id
          is_authorized = topic&.user_id == user&.id || is_this_winner
          winner_data[:shipped_at] = lpw.shipped_at if is_authorized && lpw.shipped_at
          winner_data[:collected_at] = lpw.collected_at if is_authorized && lpw.collected_at

          winner_data
        end || []

      {
        has_ticket: has_ticket,
        ticket_count: ticket_count,
        quantity: packet&.quantity || 1,
        users: users,
        winners: winners,
      }
    end

    # Send PM to winner when packet is marked as shipped
    def send_shipped_notification_pm(winner:, sender:, packet:, lottery_topic:, tracking_info:)
      # Skip notification if winner is no longer an active member
      return unless VzekcVerlosung::MemberChecker.active_member?(winner)

      packet_title = packet.title || "Paket ##{packet.ordinal}"

      message_title =
        I18n.t(
          "vzekc_verlosung.notifications.packet_shipped.title",
          locale: winner.effective_locale,
          packet_title: packet_title,
        )

      message_body =
        if tracking_info.present?
          I18n.t(
            "vzekc_verlosung.notifications.packet_shipped.body_with_tracking",
            locale: winner.effective_locale,
            username: winner.username,
            sender_username: sender.username,
            packet_title: packet_title,
            lottery_title: lottery_topic.title,
            lottery_url: "#{Discourse.base_url}#{lottery_topic.relative_url}",
            tracking_info: tracking_info,
          )
        else
          I18n.t(
            "vzekc_verlosung.notifications.packet_shipped.body",
            locale: winner.effective_locale,
            username: winner.username,
            sender_username: sender.username,
            packet_title: packet_title,
            lottery_title: lottery_topic.title,
            lottery_url: "#{Discourse.base_url}#{lottery_topic.relative_url}",
          )
        end

      PostCreator.create!(
        sender,
        title: message_title,
        raw: message_body,
        archetype: Archetype.private_message,
        target_usernames: winner.username,
        skip_validations: true,
      )
    rescue => e
      Rails.logger.error(
        "Failed to send shipped PM for packet #{packet.id} to user #{winner.username}: #{e.message}",
      )
    end

    # Notify the lottery creator that a ticket was drawn
    def notify_ticket_bought(topic, post, buyer)
      return if topic.user_id == buyer.id # Don't notify if creator drew their own ticket
      return unless VzekcVerlosung::MemberChecker.active_member?(buyer) # Skip non-members

      packet_title =
        VzekcVerlosung::TitleExtractor.extract_title(post.raw) || "Packet ##{post.post_number}"

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
      return unless VzekcVerlosung::MemberChecker.active_member?(returner) # Skip non-members

      packet_title =
        VzekcVerlosung::TitleExtractor.extract_title(post.raw) || "Packet ##{post.post_number}"

      Notification.consolidate_or_create!(
        notification_type: Notification.types[:vzekc_verlosung_ticket_returned],
        user_id: topic.user_id,
        topic_id: topic.id,
        post_number: post.post_number,
        data: { display_username: returner.username, packet_title: packet_title }.to_json,
      )
    end
  end
end
