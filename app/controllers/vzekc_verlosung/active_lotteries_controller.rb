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
          .includes(:lottery_packets, topic: [:category, { user: :primary_group }])
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
      packets = lottery.lottery_packets.where(abholerpaket: false).sort_by(&:ordinal)

      # Get all post_ids for tickets query
      packet_post_ids = packets.map(&:post_id)

      # Count unique participants across all packets
      participant_count =
        LotteryTicket.where(post_id: packet_post_ids).select(:user_id).distinct.count

      # Get tickets grouped by post_id with user data
      tickets_by_post =
        LotteryTicket.where(post_id: packet_post_ids).includes(:user).group_by(&:post_id)

      {
        id: lottery.id,
        topic_id: topic.id,
        title: topic.title,
        url: topic.relative_url,
        created_at: topic.created_at,
        ends_at: lottery.ends_at,
        drawing_mode: lottery.drawing_mode,
        packet_count: packets.sum(&:quantity),
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
        packets:
          packets.map do |packet|
            tickets = tickets_by_post[packet.post_id] || []
            {
              ordinal: packet.ordinal,
              title: packet.title,
              url: "#{topic.relative_url}/#{packet.post.post_number}",
              ticket_count: tickets.size,
              users:
                tickets.map do |ticket|
                  {
                    id: ticket.user.id,
                    username: ticket.user.username,
                    avatar_template: ticket.user.avatar_template,
                  }
                end,
            }
          end,
      }
    end
  end
end
