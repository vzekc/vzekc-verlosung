# frozen_string_literal: true

module VzekcVerlosung
  class LotteryHistoryController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME
    requires_login

    # GET /vzekc-verlosung/history/stats.json
    #
    # Returns aggregated statistics for all finished lotteries
    #
    # @return [JSON] {
    #   total_lotteries: Integer,
    #   total_packets: Integer,
    #   unique_participants: Integer,
    #   total_tickets: Integer,
    #   unique_winners: Integer
    # }
    def stats
      finished_packets =
        LotteryPacket
          .joins(:lottery)
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .where.not(winner_user_id: nil)

      total_packets = finished_packets.count

      # Count total tickets and unique participants from finished lotteries
      finished_packet_post_ids = finished_packets.pluck(:post_id)
      tickets_query = LotteryTicket.where(post_id: finished_packet_post_ids)
      total_tickets = tickets_query.count
      unique_participants = tickets_query.distinct.count(:user_id)

      render json: {
               total_lotteries: Lottery.joins(:topic).where(state: "finished").count,
               total_packets: total_packets,
               unique_participants: unique_participants,
               total_tickets: total_tickets,
               unique_winners: finished_packets.distinct.count(:winner_user_id),
             }
    end

    # GET /vzekc-verlosung/history/leaderboard.json
    #
    # Returns user leaderboards for wins, erhaltungsberichte, and tickets
    #
    # @return [JSON] {
    #   wins: [{ user: {...}, count: Integer }],
    #   berichte: [{ user: {...}, count: Integer }],
    #   tickets: [{ user: {...}, count: Integer }]
    # }
    def leaderboard
      luck_data = luck_rankings
      render json: {
               lotteries: top_lottery_creators(10),
               tickets: top_ticket_buyers(10),
               wins: top_winners(10),
               luckiest: luck_data[:luckiest],
               unluckiest: luck_data[:unluckiest],
             }
    end

    # GET /vzekc-verlosung/history/packets.json
    #
    # Returns packet leaderboard: most popular and no tickets
    #
    # @return [JSON] {
    #   popular: [Array of packets with many tickets],
    #   no_tickets: [Array of packets with no tickets, newest first]
    # }
    def packets
      render json: { popular: popular_packets(10), no_tickets: packets_without_tickets(10) }
    end

    # GET /vzekc-verlosung/history/lotteries.json
    #
    # Returns finished lotteries grouped with their packets
    #
    # Query parameters:
    # - page: Page number for pagination (default: 1)
    # - per_page: Items per page (default: 20, max: 50)
    #
    # @return [JSON] {
    #   lotteries: [Array of lottery objects with packets]
    # }
    def lotteries
      page = [params[:page].to_i, 1].max
      per_page = [[params[:per_page].to_i, 20].max, 50].min

      lottery_query =
        Lottery
          .where(state: "finished")
          .joins(:topic)
          .includes(:lottery_packets, topic: %i[category user])
          .order("topics.created_at DESC")
          .limit(per_page)
          .offset((page - 1) * per_page)

      render json: { lotteries: lottery_query.map { |lottery| build_lottery_response(lottery) } }
    end

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

    # Build lottery response with packets
    #
    # @param lottery [Lottery] The lottery
    # @return [Hash] Lottery data with packets
    def build_lottery_response(lottery)
      topic = lottery.topic
      packets_with_winners =
        lottery.lottery_packets.select { |p| p.winner_user_id.present? }.sort_by(&:ordinal)

      # Preload winners
      winner_ids = packets_with_winners.map(&:winner_user_id).compact
      winners_by_id = User.where(id: winner_ids).index_by(&:id)

      {
        id: lottery.id,
        topic_id: topic.id,
        title: topic.title,
        url: topic.relative_url,
        created_at: topic.created_at,
        drawn_at: lottery.drawn_at,
        participant_count: lottery.participant_count,
        packet_count: packets_with_winners.size,
        collected_count: packets_with_winners.count { |p| p.collected_at.present? },
        bericht_count: packets_with_winners.count { |p| p.erhaltungsbericht_topic_id.present? },
        category: {
          id: topic.category&.id,
          name: topic.category&.name,
          slug: topic.category&.slug,
          color: topic.category&.color,
        },
        creator: {
          id: topic.user&.id,
          username: topic.user&.username,
          avatar_template: topic.user&.avatar_template,
        },
        packets:
          packets_with_winners.map do |packet|
            winner = winners_by_id[packet.winner_user_id]
            {
              ordinal: packet.ordinal,
              title: packet.title,
              winner:
                if winner
                  {
                    id: winner.id,
                    username: winner.username,
                    avatar_template: winner.avatar_template,
                  }
                end,
              collected_at: packet.collected_at,
              has_bericht: packet.erhaltungsbericht_topic_id.present?,
            }
          end,
      }
    end

    # Get top lottery creators by number of finished lotteries
    #
    # @param limit [Integer] Number of results to return
    # @return [Array<Hash>] Array of { user: {...}, count: Integer }
    def top_lottery_creators(limit)
      # Get topic creators for finished lotteries
      lottery_counts =
        Lottery
          .joins(:topic)
          .where(state: "finished")
          .group("topics.user_id")
          .order("count_all DESC")
          .limit(limit)
          .count

      user_ids = lottery_counts.keys
      users_by_id = User.where(id: user_ids).index_by(&:id)

      lottery_counts
        .map do |user_id, count|
          user = users_by_id[user_id]
          next unless user

          {
            user: {
              id: user.id,
              username: user.username,
              name: user.name,
              avatar_template: user.avatar_template,
            },
            count: count,
          }
        end
        .compact
    end

    # Get top winners by packet count
    #
    # @param limit [Integer] Number of results to return
    # @return [Array<Hash>] Array of { user: {...}, count: Integer }
    def top_winners(limit)
      winner_counts =
        LotteryPacket
          .joins(:lottery)
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .where.not(winner_user_id: nil)
          .group(:winner_user_id)
          .order("count_all DESC")
          .limit(limit)
          .count

      user_ids = winner_counts.keys
      users_by_id = User.where(id: user_ids).index_by(&:id)

      winner_counts
        .map do |user_id, count|
          user = users_by_id[user_id]
          next unless user

          {
            user: {
              id: user.id,
              username: user.username,
              name: user.name,
              avatar_template: user.avatar_template,
            },
            count: count,
          }
        end
        .compact
    end

    # Get luck rankings for all participants
    #
    # @return [Hash] { luckiest: Array, unluckiest: Array }
    def luck_rankings
      # Get all finished packets with their ticket counts
      finished_packets =
        LotteryPacket
          .joins(:lottery)
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .where.not(winner_user_id: nil)
          .pluck(:id, :post_id, :winner_user_id)

      return { luckiest: [], unluckiest: [] } if finished_packets.empty?

      # Get ticket counts per packet
      post_ids = finished_packets.map { |_, post_id, _| post_id }.compact
      ticket_counts_by_post =
        LotteryTicket.where(post_id: post_ids).group(:post_id).count

      # Get user ticket counts per packet
      user_tickets =
        LotteryTicket
          .where(post_id: post_ids)
          .group(:post_id, :user_id)
          .count

      # Calculate expected wins and actual wins per user
      user_stats = Hash.new { |h, k| h[k] = { expected: 0.0, wins: 0 } }

      finished_packets.each do |_packet_id, post_id, winner_user_id|
        total_tickets = ticket_counts_by_post[post_id] || 0
        next if total_tickets.zero?

        # Add expected wins for all participants in this packet
        user_tickets.each do |(p_id, user_id), count|
          next unless p_id == post_id

          user_stats[user_id][:expected] += count.to_f / total_tickets
        end

        # Add actual win
        user_stats[winner_user_id][:wins] += 1
      end

      # Calculate luck factor for all users
      all_rankings =
        user_stats.map do |user_id, stats|
          luck = stats[:wins] - stats[:expected]
          { user_id: user_id, luck: luck, wins: stats[:wins], expected: stats[:expected] }
        end

      # Split into luckiest (positive) and unluckiest (negative)
      luckiest = all_rankings.select { |e| e[:luck] > 0 }.sort_by { |e| -e[:luck] }.first(10)
      unluckiest = all_rankings.select { |e| e[:luck] < 0 }.sort_by { |e| e[:luck] }.first(10)

      # Load all users needed
      all_user_ids = (luckiest + unluckiest).map { |e| e[:user_id] }
      users_by_id = User.where(id: all_user_ids).index_by(&:id)

      {
        luckiest: format_luck_entries(luckiest, users_by_id),
        unluckiest: format_luck_entries(unluckiest, users_by_id),
      }
    end

    # Format luck entries with user data
    #
    # @param entries [Array] Raw luck entries
    # @param users_by_id [Hash] Users indexed by ID
    # @return [Array<Hash>] Formatted entries
    def format_luck_entries(entries, users_by_id)
      entries
        .map do |entry|
          user = users_by_id[entry[:user_id]]
          next unless user

          {
            user: {
              id: user.id,
              username: user.username,
              name: user.name,
              avatar_template: user.avatar_template,
            },
            luck: entry[:luck].round(2),
            wins: entry[:wins],
            expected: entry[:expected].round(2),
          }
        end
        .compact
    end

    # Get top erhaltungsbericht writers
    # Only counts packets where erhaltungsbericht_required is true
    #
    # @param limit [Integer] Number of results to return
    # @return [Array<Hash>] Array of { user: {...}, count: Integer }
    def top_bericht_writers(limit)
      bericht_counts =
        LotteryPacket
          .joins(:lottery)
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .where(erhaltungsbericht_required: true)
          .where.not(winner_user_id: nil)
          .where.not(erhaltungsbericht_topic_id: nil)
          .group(:winner_user_id)
          .order("count_all DESC")
          .limit(limit)
          .count

      user_ids = bericht_counts.keys
      users_by_id = User.where(id: user_ids).index_by(&:id)

      bericht_counts
        .map do |user_id, count|
          user = users_by_id[user_id]
          next unless user

          {
            user: {
              id: user.id,
              username: user.username,
              name: user.name,
              avatar_template: user.avatar_template,
            },
            count: count,
          }
        end
        .compact
    end

    # Get top ticket buyers by total tickets purchased across all finished lotteries
    #
    # @param limit [Integer] Number of results to return
    # @return [Array<Hash>] Array of { user: {...}, count: Integer }
    def top_ticket_buyers(limit)
      # Get post_ids from finished lotteries
      finished_packet_post_ids =
        LotteryPacket
          .joins(:lottery)
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .pluck(:post_id)

      ticket_counts =
        LotteryTicket
          .where(post_id: finished_packet_post_ids)
          .group(:user_id)
          .order("count_all DESC")
          .limit(limit)
          .count

      user_ids = ticket_counts.keys
      users_by_id = User.where(id: user_ids).index_by(&:id)

      ticket_counts
        .map do |user_id, count|
          user = users_by_id[user_id]
          next unless user

          {
            user: {
              id: user.id,
              username: user.username,
              name: user.name,
              avatar_template: user.avatar_template,
            },
            count: count,
          }
        end
        .compact
    end

    # Get packets with most tickets from finished lotteries
    #
    # @param limit [Integer] Number of results to return
    # @return [Array<Hash>] Array of packet data with ticket count
    def popular_packets(limit)
      # Get packets from finished lotteries
      finished_packet_post_ids =
        LotteryPacket.joins(:lottery).where(vzekc_verlosung_lotteries: { state: "finished" }).pluck(:post_id).compact

      # Count tickets per post_id
      ticket_counts_by_post =
        LotteryTicket
          .where(post_id: finished_packet_post_ids)
          .group(:post_id)
          .order("count_all DESC")
          .limit(limit)
          .count

      post_ids = ticket_counts_by_post.keys
      packets_by_post_id =
        LotteryPacket
          .includes(:post, lottery: { topic: :category })
          .where(post_id: post_ids)
          .index_by(&:post_id)

      ticket_counts_by_post
        .map do |post_id, ticket_count|
          packet = packets_by_post_id[post_id]
          next unless packet&.lottery&.topic

          build_packet_leaderboard_entry(packet, ticket_count)
        end
        .compact
    end

    # Get packets with no tickets from finished lotteries, newest first
    #
    # @param limit [Integer] Number of results to return
    # @return [Array<Hash>] Array of packet data
    def packets_without_tickets(limit)
      # Get post_ids that have tickets
      post_ids_with_tickets = LotteryTicket.distinct.pluck(:post_id)

      packets_without =
        LotteryPacket
          .joins(:post, lottery: :topic)
          .includes(lottery: { topic: :category })
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .where.not(post_id: post_ids_with_tickets)
          .order("topics.created_at DESC")
          .limit(limit)

      packets_without.map { |packet| build_packet_leaderboard_entry(packet, 0) }
    end

    # Build packet leaderboard entry
    #
    # @param packet [LotteryPacket] The packet
    # @param ticket_count [Integer] Number of tickets
    # @return [Hash] Packet data for leaderboard
    def build_packet_leaderboard_entry(packet, ticket_count)
      topic = packet.lottery.topic
      post = packet.post

      {
        id: packet.id,
        title: packet.title,
        ticket_count: ticket_count,
        url: "#{topic.relative_url}/#{post.post_number}",
        lottery: {
          id: topic.id,
          title: topic.title,
          url: topic.relative_url,
        },
        category: {
          id: topic.category&.id,
          name: topic.category&.name,
          color: topic.category&.color,
        },
      }
    end
  end
end
