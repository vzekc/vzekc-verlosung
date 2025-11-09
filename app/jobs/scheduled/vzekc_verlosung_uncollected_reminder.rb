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

          # Find all uncollected packets in this lottery
          uncollected_packets =
            lottery
              .lottery_packets
              .uncollected
              .includes(:winner, :post)
              .map do |packet|
                post = packet.post
                packet_title =
                  extract_title_from_markdown(post.raw) || "Packet ##{post.post_number}"
                {
                  post_number: post.post_number,
                  title: packet_title,
                  winner: packet.winner.username,
                }
              end

          # Send reminder if there are uncollected packets
          if uncollected_packets.any?
            send_uncollected_reminder(lottery.topic, uncollected_packets, days_since_drawn)
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

    def extract_title_from_markdown(raw)
      match = raw.match(/^#\s+(.+)$/)
      match ? match[1].strip : nil
    end
  end
end
