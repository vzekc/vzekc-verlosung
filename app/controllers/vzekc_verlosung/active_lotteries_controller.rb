# frozen_string_literal: true

module VzekcVerlosung
  class ActiveLotteriesController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    # GET /vzekc-verlosung/active.json
    #
    # Returns a list of all active lotteries ordered by ending soonest first
    #
    # @return [JSON] {
    #   lotteries: [Array of lottery objects]
    # }
    def index
      lotteries =
        Lottery
          .joins(:topic)
          .where(state: "active")
          .includes(topic: [:category, { user: :primary_group }])
          .order(ends_at: :asc)

      render json: { lotteries: lotteries.map { |lottery| build_lottery_response(lottery) } }
    end

    private

    # Build lottery response data
    #
    # @param lottery [Lottery] The lottery
    # @return [Hash] Lottery data
    def build_lottery_response(lottery)
      topic = lottery.topic

      # Count packets and participants
      packet_count = lottery.lottery_packets.count
      packet_post_ids = lottery.lottery_packets.pluck(:post_id)
      participant_count =
        LotteryTicket.where(post_id: packet_post_ids).select(:user_id).distinct.count

      {
        id: lottery.id,
        topic_id: topic.id,
        title: topic.title,
        url: topic.relative_url,
        created_at: topic.created_at,
        ends_at: lottery.ends_at,
        drawing_mode: lottery.drawing_mode,
        packet_count: packet_count,
        participant_count: participant_count,
        category: {
          id: topic.category&.id,
          name: topic.category&.name,
          slug: topic.category&.slug,
          color: topic.category&.color,
        },
        creator: {
          id: topic.user&.id,
          username: topic.user&.username,
          name: topic.user&.name,
          avatar_template: topic.user&.avatar_template,
          admin: topic.user&.admin,
          moderator: topic.user&.moderator,
          title: topic.user&.title,
          primary_group_name: topic.user&.primary_group&.name,
        },
      }
    end
  end
end
