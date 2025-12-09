# frozen_string_literal: true

module VzekcVerlosung
  class UserStatsController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :find_user

    # GET /vzekc-verlosung/users/:username.json
    #
    # Returns lottery statistics and history for a specific user
    #
    # @return [JSON] User lottery statistics including:
    #   - stats: Aggregated statistics
    #   - luck: Luck factor calculation
    #   - won_packets: List of packets won
    #   - lotteries_created: List of lotteries created
    #   - pickups: List of pickups completed
    def show
      render json: {
               stats: build_stats,
               luck: build_luck_data,
               won_packets: build_won_packets,
               lotteries_created: build_lotteries_created,
               pickups: build_pickups,
             }
    end

    private

    # Find the user by username from URL params
    def find_user
      @user = User.find_by_username(params[:username])
      raise Discourse::NotFound unless @user
    end

    # Build aggregated statistics for the user
    #
    # @return [Hash] Statistics including ticket count, wins, lotteries, pickups
    def build_stats
      # Count tickets purchased (in finished lotteries)
      finished_packet_post_ids =
        LotteryPacket
          .joins(:lottery)
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .pluck(:post_id)

      tickets_count = LotteryTicket.where(user_id: @user.id, post_id: finished_packet_post_ids).count

      # Count packets won
      packets_won =
        LotteryPacket
          .joins(:lottery)
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .where(winner_user_id: @user.id)
          .count

      # Count lotteries created (finished only)
      lotteries_created =
        Lottery.joins(:topic).where(state: "finished").where(topics: { user_id: @user.id }).count

      # Count pickups completed
      pickups_count = PickupOffer.where(user_id: @user.id, state: "picked_up").count

      # Count erhaltungsberichte written (for packets won)
      berichte_count =
        LotteryPacket
          .joins(:lottery)
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .where(winner_user_id: @user.id)
          .where(erhaltungsbericht_required: true)
          .where.not(erhaltungsbericht_topic_id: nil)
          .count

      {
        tickets_count: tickets_count,
        packets_won: packets_won,
        lotteries_created: lotteries_created,
        pickups_count: pickups_count,
        berichte_count: berichte_count,
      }
    end

    # Calculate the user's luck factor (Glückspilz/Pechvogel)
    #
    # @return [Hash] Luck data with expected wins, actual wins, and luck factor
    def build_luck_data
      # Get all finished packets
      finished_packets =
        LotteryPacket
          .joins(:lottery)
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .where.not(winner_user_id: nil)
          .pluck(:id, :post_id, :winner_user_id)

      return { luck: 0, wins: 0, expected: 0, participated: 0 } if finished_packets.empty?

      # Get ticket counts per packet
      post_ids = finished_packets.map { |_, post_id, _| post_id }.compact
      ticket_counts_by_post = LotteryTicket.where(post_id: post_ids).group(:post_id).count

      # Get user's tickets per packet
      user_tickets_by_post =
        LotteryTicket.where(user_id: @user.id, post_id: post_ids).group(:post_id).count

      expected_wins = 0.0
      actual_wins = 0
      packets_participated = 0

      finished_packets.each do |_packet_id, post_id, winner_user_id|
        user_ticket_count = user_tickets_by_post[post_id] || 0
        next if user_ticket_count.zero?

        packets_participated += 1
        total_tickets = ticket_counts_by_post[post_id] || 0
        next if total_tickets.zero?

        expected_wins += user_ticket_count.to_f / total_tickets
        actual_wins += 1 if winner_user_id == @user.id
      end

      {
        luck: (actual_wins - expected_wins).round(2),
        wins: actual_wins,
        expected: expected_wins.round(2),
        participated: packets_participated,
      }
    end

    # Build list of packets the user has won
    #
    # @return [Array<Hash>] List of won packets with details
    def build_won_packets
      packets =
        LotteryPacket
          .joins(:post, lottery: :topic)
          .includes(lottery: { topic: :category }, erhaltungsbericht_topic: [])
          .where(vzekc_verlosung_lotteries: { state: "finished" })
          .where(winner_user_id: @user.id)
          .order("vzekc_verlosung_lottery_packets.won_at DESC")
          .limit(50)

      packets.map do |packet|
        topic = packet.lottery.topic
        {
          id: packet.id,
          title: packet.title,
          url: "#{topic.relative_url}/#{packet.post.post_number}",
          won_at: packet.won_at,
          collected_at: packet.collected_at,
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
          erhaltungsbericht_required: packet.erhaltungsbericht_required,
          erhaltungsbericht:
            if packet.erhaltungsbericht_topic
              {
                id: packet.erhaltungsbericht_topic.id,
                title: packet.erhaltungsbericht_topic.title,
                url: packet.erhaltungsbericht_topic.relative_url,
              }
            end,
        }
      end
    end

    # Build list of lotteries the user has created
    #
    # @return [Array<Hash>] List of created lotteries with details
    def build_lotteries_created
      lotteries =
        Lottery
          .joins(:topic)
          .includes(:lottery_packets, topic: :category)
          .where(state: "finished")
          .where(topics: { user_id: @user.id })
          .order("vzekc_verlosung_lotteries.ends_at DESC")
          .limit(50)

      lotteries.map do |lottery|
        topic = lottery.topic
        packets_with_winners = lottery.lottery_packets.select { |p| p.winner_user_id.present? }
        {
          id: lottery.id,
          topic_id: topic.id,
          title: topic.title,
          url: topic.relative_url,
          ends_at: lottery.ends_at,
          drawn_at: lottery.drawn_at,
          packet_count: packets_with_winners.size,
          participant_count: lottery.participant_count,
          category: {
            id: topic.category&.id,
            name: topic.category&.name,
            color: topic.category&.color,
          },
        }
      end
    end

    # Build list of pickups the user has completed
    #
    # @return [Array<Hash>] List of completed pickups with details
    def build_pickups
      pickup_offers =
        PickupOffer
          .joins(donation: :topic)
          .includes(donation: { topic: :category })
          .where(user_id: @user.id, state: "picked_up")
          .order("vzekc_verlosung_pickup_offers.picked_up_at DESC")
          .limit(50)

      pickup_offers.map do |offer|
        donation = offer.donation
        topic = donation.topic
        next unless topic

        lottery = donation.lottery
        {
          id: offer.id,
          picked_up_at: offer.picked_up_at,
          donation: {
            id: donation.id,
            topic_id: topic.id,
            title: topic.title,
            url: topic.relative_url,
          },
          category: {
            id: topic.category&.id,
            name: topic.category&.name,
            color: topic.category&.color,
          },
          outcome:
            if lottery&.active? || lottery&.finished?
              {
                type: "lottery",
                id: lottery.topic_id,
                title: lottery.topic&.title,
                url: lottery.topic&.relative_url,
              }
            elsif donation.erhaltungsbericht_topic_id.present?
              bericht_topic = donation.erhaltungsbericht_topic
              {
                type: "erhaltungsbericht",
                id: bericht_topic&.id,
                title: bericht_topic&.title,
                url: bericht_topic&.relative_url,
              }
            end,
        }
      end.compact
    end
  end
end
