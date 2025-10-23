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

      ticket = VzekcVerlosung::LotteryTicket.new(post_id: post.id, user_id: current_user.id)

      if ticket.save
        render json: success_json.merge(has_ticket: true)
      else
        render json: failed_json.merge(errors: ticket.errors.full_messages), status: :unprocessable_entity
      end
    end

    # DELETE /vzekc_verlosung/tickets/:post_id
    # Removes the lottery ticket for the current user and post
    def destroy
      ticket = VzekcVerlosung::LotteryTicket.find_by(post_id: params[:post_id], user_id: current_user.id)

      if ticket
        ticket.destroy
        render json: success_json.merge(has_ticket: false)
      else
        render json: failed_json.merge(errors: ["Ticket not found"]), status: :not_found
      end
    end

    # GET /vzekc_verlosung/tickets/status/:post_id
    # Returns whether the current user has a ticket for the post
    def status
      has_ticket = VzekcVerlosung::LotteryTicket.exists?(post_id: params[:post_id], user_id: current_user.id)
      render json: { has_ticket: has_ticket }
    end
  end
end
