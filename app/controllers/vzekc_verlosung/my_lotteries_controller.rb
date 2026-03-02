# frozen_string_literal: true

module VzekcVerlosung
  class MyLotteriesController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in, only: %i[index active]

    # Serves the Ember app shell for direct page loads at /my-lotteries
    def page
      render html: "", layout: true
    end

    # GET /vzekc-verlosung/my-lotteries/active.json
    def active
      lotteries =
        Lottery
          .joins(:topic)
          .where(topics: { user_id: current_user.id })
          .where(state: "active")
          .includes(:lottery_packets, topic: :category)
          .order(ends_at: :asc)

      render json: { lotteries: lotteries.map { |lottery| serialize_active_lottery(lottery) } }
    end

    # GET /vzekc-verlosung/my-lotteries.json
    def index
      lottery_ids =
        Lottery
          .joins(:topic)
          .where(topics: { user_id: current_user.id })
          .where.not(drawn_at: nil)
          .pluck(:id)

      lotteries_with_pending =
        Lottery
          .where(id: lottery_ids)
          .joins(lottery_packets: :lottery_packet_winners)
          .where.not(vzekc_verlosung_lottery_packet_winners: { fulfillment_state: "completed" })
          .distinct

      lotteries =
        lotteries_with_pending.includes(
          :topic,
          lottery_packets: {
            lottery_packet_winners: :winner,
          },
        ).order(drawn_at: :desc)

      render json: { lotteries: lotteries.map { |lottery| serialize_lottery(lottery) } }
    end

    private

    def serialize_active_lottery(lottery)
      topic = lottery.topic
      packets = lottery.lottery_packets.where(abholerpaket: false).sort_by(&:ordinal)

      packet_post_ids = packets.map(&:post_id)

      participant_count =
        LotteryTicket.where(post_id: packet_post_ids).select(:user_id).distinct.count

      tickets_by_post =
        LotteryTicket.where(post_id: packet_post_ids).includes(:user).group_by(&:post_id)

      {
        id: lottery.id,
        topic_id: topic.id,
        title: topic.title,
        slug: topic.slug,
        url: topic.relative_url,
        ends_at: lottery.ends_at,
        drawing_mode: lottery.drawing_mode,
        drawn_at: lottery.drawn_at,
        participant_count: participant_count,
        packets:
          packets.map do |packet|
            tickets = tickets_by_post[packet.post_id] || []
            {
              ordinal: packet.ordinal,
              title: packet.title,
              post_id: packet.post_id,
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

    def serialize_lottery(lottery)
      topic = lottery.topic
      packets = lottery.lottery_packets.sort_by(&:ordinal)

      winner_groups = {}
      packets.each do |packet|
        packet.lottery_packet_winners.each do |entry|
          next if entry.fulfillment_state == "completed"

          winner_groups[entry.winner_user_id] ||= {
            user: serialize_user(entry.winner),
            winner_pm_topic_id: nil,
            entries: [],
          }

          winner_groups[entry.winner_user_id][:winner_pm_topic_id] ||= entry.winner_pm_topic_id
          winner_groups[entry.winner_user_id][:entries] << serialize_entry(packet, entry)
        end
      end

      {
        id: lottery.id,
        topic_id: topic.id,
        topic_title: topic.title,
        topic_slug: topic.slug,
        drawn_at: lottery.drawn_at&.iso8601,
        winner_groups: winner_groups.values,
      }
    end

    def serialize_entry(packet, entry)
      {
        post_id: packet.post_id,
        ordinal: packet.ordinal,
        title: packet.title,
        quantity: packet.quantity,
        instance_number: entry.instance_number,
        fulfillment_state: entry.fulfillment_state,
        shipped_at: entry.shipped_at&.iso8601,
        collected_at: entry.collected_at&.iso8601,
        tracking_info: entry.tracking_info,
        winner_pm_topic_id: entry.winner_pm_topic_id,
        erhaltungsbericht_topic_id: entry.erhaltungsbericht_topic_id,
        erhaltungsbericht_required: packet.erhaltungsbericht_required,
        abholerpaket: packet.abholerpaket,
        note: packet.note,
        username: entry.winner.username,
      }
    end

    def serialize_user(user)
      return unless user

      {
        id: user.id,
        username: user.username,
        name: user.name,
        avatar_template: user.avatar_template,
      }
    end
  end
end
