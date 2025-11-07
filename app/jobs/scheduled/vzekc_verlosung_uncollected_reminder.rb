# frozen_string_literal: true

module Jobs
  class VzekcVerlosungUncollectedReminder < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      # Find all finished lotteries with drawn results
      Topic
        .where(deleted_at: nil)
        .joins(:_custom_fields)
        .where(topic_custom_fields: { name: "lottery_state", value: "finished" })
        .find_each do |topic|
          next unless topic.custom_fields["lottery_results"].present?

          # Check when the lottery was drawn
          drawn_at = topic.custom_fields["lottery_drawn_at"]
          next unless drawn_at.present?

          drawn_date = drawn_at.is_a?(String) ? Time.zone.parse(drawn_at) : drawn_at
          days_since_drawn = (Time.zone.now - drawn_date).to_i / 1.day

          # Only send reminder every 7 days (on days 7, 14, 21, etc.)
          next unless (days_since_drawn % 7).zero? && days_since_drawn > 0

          # Find all packet posts in this lottery
          packet_posts =
            Post
              .where(topic_id: topic.id)
              .joins(:_custom_fields)
              .where(post_custom_fields: { name: "is_lottery_packet", value: "t" })

          # Find packets with winners but not marked as collected
          uncollected_packets = []
          packet_posts.each do |post|
            winner = post.custom_fields["lottery_winner"]
            collected_at = post.custom_fields["packet_collected_at"]

            # Has winner but not collected
            if winner.present? && collected_at.blank?
              packet_title = extract_title_from_markdown(post.raw) || "Packet ##{post.post_number}"
              uncollected_packets << {
                post_number: post.post_number,
                title: packet_title,
                winner: winner,
              }
            end
          end

          # Send reminder if there are uncollected packets
          if uncollected_packets.any?
            send_uncollected_reminder(topic, uncollected_packets, days_since_drawn)
          end
        end
    end

    private

    def send_uncollected_reminder(topic, uncollected_packets, days_since_drawn)
      return unless topic.user_id.present?

      owner = User.find_by(id: topic.user_id)
      return unless owner

      # Format packet list for PM body
      packet_list =
        uncollected_packets
          .map { |p| "- #{p[:title]} (Winner: #{p[:winner]})" }
          .join("\n")

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
