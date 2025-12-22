# frozen_string_literal: true

module Jobs
  class VzekcVerlosungUncollectedReminder < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      # Find all finished lotteries with drawn results, grouped by lottery
      VzekcVerlosung::Lottery
        .finished
        .where.not(drawn_at: nil)
        .includes(:topic)
        .find_each do |lottery|
          next if lottery.drawn_at.blank?

          days_since_drawn = (Time.zone.now - lottery.drawn_at).to_i / 1.day

          # Only send reminder every 7 days (on days 7, 14, 21, etc.)
          next if (days_since_drawn % 7).nonzero? || days_since_drawn <= 0

          # Find all uncollected winner entries in this lottery
          uncollected_entries =
            VzekcVerlosung::LotteryPacketWinner
              .uncollected
              .joins(lottery_packet: :post)
              .includes(:winner, lottery_packet: :post)
              .where(vzekc_verlosung_lottery_packets: { lottery_id: lottery.id })
              .map do |entry|
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
                }
              end

          # Send reminder if there are uncollected entries
          if uncollected_entries.any?
            send_uncollected_reminder(lottery.topic, uncollected_entries, days_since_drawn)
          end
        end
    end

    private

    def send_uncollected_reminder(topic, uncollected_packets, days_since_drawn)
      return if topic.user_id.blank?

      owner = User.find_by(id: topic.user_id)
      return unless owner

      # Format packet list for PM body
      packet_list =
        uncollected_packets.map { |p| "- #{p[:title]} (Winner: #{p[:winner]})" }.join("\n")

      # Send reminder PM
      PostCreator.create!(
        Discourse.system_user,
        title:
          I18n.t(
            "vzekc_verlosung.reminders.uncollected.title",
            locale: owner.effective_locale,
            uncollected_count: uncollected_packets.count,
          ),
        raw:
          I18n.t(
            "vzekc_verlosung.reminders.uncollected.body",
            locale: owner.effective_locale,
            username: owner.username,
            topic_title: topic.title,
            days_since_drawn: days_since_drawn,
            packet_list: packet_list,
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
          ),
        archetype: Archetype.private_message,
        subtype: TopicSubtype.system_message,
        target_usernames: owner.username,
        skip_validations: true,
      )
    end
  end
end
