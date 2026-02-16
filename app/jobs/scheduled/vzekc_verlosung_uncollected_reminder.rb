# frozen_string_literal: true

module Jobs
  class VzekcVerlosungUncollectedReminder < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      VzekcVerlosung::Lottery
        .finished
        .where.not(drawn_at: nil)
        .includes(:topic)
        .find_each do |lottery|
          next if lottery.drawn_at.blank?

          days_since_drawn = (Time.zone.now - lottery.drawn_at).to_i / 1.day

          # Only send reminder every 7 days (on days 7, 14, 21, etc.)
          next if (days_since_drawn % 7).nonzero? || days_since_drawn <= 0

          topic = lottery.topic
          next if topic.blank? || topic.user_id.blank?

          owner = User.find_by(id: topic.user_id)
          next unless owner

          uncollected_entries =
            VzekcVerlosung::LotteryPacketWinner
              .uncollected
              .joins(lottery_packet: :post)
              .includes(:winner, lottery_packet: :post)
              .where(vzekc_verlosung_lottery_packets: { lottery_id: lottery.id })
              .where.not(vzekc_verlosung_lottery_packets: { notifications_silenced: true })
              .filter_map do |entry|
                next unless VzekcVerlosung::MemberChecker.active_member?(entry.winner)

                packet = entry.lottery_packet
                post = packet.post
                packet_title =
                  VzekcVerlosung::TitleExtractor.extract_title(post.raw) ||
                    "Packet ##{post.post_number}"
                title_with_instance =
                  packet.quantity > 1 ? "#{packet_title} (##{entry.instance_number})" : packet_title
                {
                  post_number: post.post_number,
                  title: title_with_instance,
                  winner: entry.winner.username,
                  winner_user_id: entry.winner.id,
                  winner_pm_topic_id: entry.winner_pm_topic_id,
                  fulfillment_state: entry.fulfillment_state,
                }
              end

          next if uncollected_entries.none?

          send_owner_reminder(owner, topic, uncollected_entries, days_since_drawn)
          send_winner_reminders(owner, topic, uncollected_entries, days_since_drawn)
        end
    end

    private

    def send_owner_reminder(owner, topic, uncollected_entries, days_since_drawn)
      VzekcVerlosung::NotificationService.notify(
        :uncollected_owner_reminder,
        recipient: owner,
        context: {
          lottery_topic: topic,
          uncollected_packets: uncollected_entries,
          days_since_drawn: days_since_drawn,
        },
      )
    end

    def send_winner_reminders(owner, topic, uncollected_entries, days_since_drawn)
      # Only remind winners about shipped packets (they can't act on won packets)
      shipped_entries = uncollected_entries.select { |e| e[:fulfillment_state] == "shipped" }
      return if shipped_entries.none?

      # Group by winner, skip if winner is the lottery owner (already covered)
      shipped_entries
        .group_by { |e| e[:winner_user_id] }
        .each do |winner_user_id, entries|
          next if winner_user_id == owner.id

          winner = User.find_by(id: winner_user_id)
          next unless winner

          VzekcVerlosung::NotificationService.notify(
            :uncollected_winner_reminder,
            recipient: winner,
            context: {
              lottery_topic: topic,
              uncollected_packets: entries,
              days_since_drawn: days_since_drawn,
            },
          )
        end
    end
  end
end
