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
      render json: success_json.merge(ticket_packet_status_response(params[:post_id]))
    end

    # GET /vzekc_verlosung/tickets/packet-status/:post_id
    # Returns whether the current user has a ticket for a lottery packet post, total count, and list of users
    def packet_status
      render json: ticket_packet_status_response(params[:post_id])
    end

    private

    def ticket_packet_status_response(post_id)
      has_ticket = VzekcVerlosung::LotteryTicket.exists?(post_id: post_id, user_id: current_user.id)

      tickets = VzekcVerlosung::LotteryTicket.where(post_id: post_id).includes(:user)
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
      post = Post.find_by(id: post_id)
      winner_username = post&.custom_fields&.dig("lottery_winner")
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

      { has_ticket: has_ticket, ticket_count: ticket_count, users: users, winner: winner }
    end
  end
end
