# frozen_string_literal: true

module VzekcVerlosung
  class LotteryHistoryController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME
    requires_login

    # GET /vzekc-verlosung/history.json
    #
    # Returns a flat list of all packets from finished lotteries
    #
    # Query parameters:
    # - search: Filter by lottery or packet title (case-insensitive)
    # - sort: Sort order (date_desc, date_asc, lottery_asc, lottery_desc)
    # - page: Page number for pagination (default: 1)
    # - per_page: Items per page (default: 50, max: 100)
    #
    # @return [JSON] {
    #   packets: [Array of packet objects with lottery info and winners]
    # }
    def index
      search = params[:search]
      sort = params[:sort] || "date_desc"
      page = [params[:page].to_i, 1].max
      per_page = [[params[:per_page].to_i, 50].max, 100].min

      # Build query for packets from finished lotteries with winners
      packets_query =
        LotteryPacket
          .joins(lottery: :topic)
          .joins(:post)
          .joins(:winner)
          .left_joins(:erhaltungsbericht_topic)
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .where.not(winner_user_id: nil)
          .includes(lottery: { topic: %i[category user] })

      # Apply search filter at SQL level
      if search.present?
        search_term = "%#{search.downcase}%"
        packets_query =
          packets_query.where(
            "LOWER(topics.title) LIKE ? OR LOWER(vzekc_verlosung_lottery_packets.title) LIKE ?",
            search_term,
            search_term,
          )
      end

      # Apply sorting at SQL level
      packets_query =
        case sort
        when "date_asc"
          packets_query.order("topics.created_at ASC")
        when "lottery_asc"
          packets_query.order("LOWER(topics.title) ASC, topics.created_at ASC")
        when "lottery_desc"
          packets_query.order("LOWER(topics.title) DESC, topics.created_at DESC")
        else # date_desc
          packets_query.order("topics.created_at DESC")
        end

      # Paginate
      packets_query = packets_query.limit(per_page).offset((page - 1) * per_page)

      # Build response
      all_packets = packets_query.map { |packet| build_packet_response(packet) }

      render json: { packets: all_packets }
    end

    private

    # Build packet response data
    #
    # @param packet [LotteryPacket] The lottery packet
    # @return [Hash] Packet data with lottery and winner info
    def build_packet_response(packet)
      topic = packet.lottery.topic
      post = packet.post

      {
        # Packet info
        post_id: post.id,
        post_number: post.post_number,
        ordinal: packet.ordinal,
        title: packet.title,
        packet_url: "#{topic.relative_url}/#{post.post_number}",
        # Lottery info
        lottery_id: topic.id,
        lottery_title: topic.title,
        lottery_url: topic.relative_url,
        lottery_created_at: topic.created_at,
        lottery_drawn_at: packet.lottery.drawn_at,
        category: {
          id: topic.category&.id,
          name: topic.category&.name,
          slug: topic.category&.slug,
          color: topic.category&.color,
        },
        # Winner info
        winner: {
          id: packet.winner.id,
          username: packet.winner.username,
          name: packet.winner.name,
          avatar_template: packet.winner.avatar_template,
        },
        collected_at: packet.collected_at,
        won_at: packet.won_at,
        # Erhaltungsbericht info
        erhaltungsbericht_required: packet.erhaltungsbericht_required,
        erhaltungsbericht:
          if packet.erhaltungsbericht_topic
            {
              topic_id: packet.erhaltungsbericht_topic.id,
              title: packet.erhaltungsbericht_topic.title,
              slug: packet.erhaltungsbericht_topic.slug,
              url: packet.erhaltungsbericht_topic.relative_url,
              created_at: packet.erhaltungsbericht_topic.created_at,
            }
          else
            nil
          end,
      }
    end
  end
end
