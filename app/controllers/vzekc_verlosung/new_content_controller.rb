# frozen_string_literal: true

module VzekcVerlosung
  # Controller for checking if there is new (unread) content for the current user
  #
  # Returns boolean flags for each sidebar section indicating whether
  # new content exists that the user hasn't read yet.
  #
  class NewContentController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in

    # GET /vzekc-verlosung/has-new-content.json
    #
    # @return [JSON] { donations: bool, lotteries: bool, erhaltungsberichte: bool, merch_packets: bool, has_won_packets: bool }
    def index
      render json: {
               donations: VzekcVerlosung.has_unread_donations?(current_user.id),
               lotteries: VzekcVerlosung.has_unread_lotteries?(current_user.id),
               erhaltungsberichte: VzekcVerlosung.has_unread_erhaltungsberichte?(current_user.id),
               merch_packets: has_pending_merch_packets?,
               has_won_packets:
                 VzekcVerlosung::LotteryPacketWinner.where(winner_user_id: current_user.id).exists?,
               has_open_lotteries: has_open_lotteries?,
             }
    end

    private

    # Check for pending merch packets (only for merch handlers)
    #
    # @return [Boolean]
    def has_pending_merch_packets?
      return false unless guardian.can_manage_merch_packets?

      VzekcVerlosung.has_pending_merch_packets?
    end

    # Check if user owns any drawn lotteries with pending fulfillment
    #
    # @return [Boolean]
    def has_open_lotteries?
      lottery_ids =
        VzekcVerlosung::Lottery
          .joins(:topic)
          .where(topics: { user_id: current_user.id })
          .where.not(drawn_at: nil)
          .pluck(:id)

      return false if lottery_ids.empty?

      VzekcVerlosung::LotteryPacketWinner
        .joins(:lottery_packet)
        .where(vzekc_verlosung_lottery_packets: { lottery_id: lottery_ids })
        .where.not(fulfillment_state: "completed")
        .exists?
    end
  end
end
