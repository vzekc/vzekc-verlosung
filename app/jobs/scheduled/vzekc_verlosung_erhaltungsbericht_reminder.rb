# frozen_string_literal: true

module Jobs
  class VzekcVerlosungErhaltungsberichtReminder < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled
      return if SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id.blank?

      # Find all finished lotteries with drawn results
      Topic
        .where(deleted_at: nil)
        .joins(:_custom_fields)
        .where(topic_custom_fields: { name: "lottery_state", value: "finished" })
        .find_each do |topic|
          next if topic.custom_fields["lottery_results"].blank?

          # Find all packet posts in this lottery
          packet_posts =
            Post
              .where(topic_id: topic.id)
              .joins(:_custom_fields)
              .where(post_custom_fields: { name: "is_lottery_packet", value: "t" })

          # Check each packet for missing Erhaltungsberichte
          packet_posts.each do |post|
            winner_username = post.custom_fields["lottery_winner"]
            collected_at = post.custom_fields["packet_collected_at"]
            erhaltungsbericht_topic_id = post.custom_fields["erhaltungsbericht_topic_id"]

            # Skip if no winner or not collected yet
            next if winner_username.blank? || collected_at.blank?

            # Skip if Erhaltungsbericht already created
            next if erhaltungsbericht_topic_id.present?

            # Calculate days since collection
            collected_date =
              collected_at.is_a?(String) ? Time.zone.parse(collected_at) : collected_at
            days_since_collected = (Time.zone.now - collected_date).to_i / 1.day

            # Only send reminder every 7 days (on days 7, 14, 21, etc.)
            next if (days_since_collected % 7).nonzero? || days_since_collected <= 0

            # Find the winner user
            winner = User.find_by(username: winner_username)
            next unless winner

            # Send reminder
            send_erhaltungsbericht_reminder(winner, topic, post, days_since_collected)
          end
        end
    end

    private

    def send_erhaltungsbericht_reminder(user, lottery_topic, packet_post, days_since_collected)
      packet_title =
        extract_title_from_markdown(packet_post.raw) || "Paket ##{packet_post.post_number}"
      packet_url =
        "#{Discourse.base_url}/t/#{lottery_topic.slug}/#{lottery_topic.id}/#{packet_post.post_number}"

      # Send reminder PM
      PostCreator.create!(
        Discourse.system_user,
        title:
          I18n.t(
            "vzekc_verlosung.reminders.erhaltungsbericht.title",
            locale: user.effective_locale,
            packet_title: packet_title,
          ),
        raw:
          I18n.t(
            "vzekc_verlosung.reminders.erhaltungsbericht.body",
            locale: user.effective_locale,
            username: user.username,
            lottery_title: lottery_topic.title,
            packet_title: packet_title,
            days_since_collected: days_since_collected,
            packet_url: packet_url,
          ),
        archetype: Archetype.private_message,
        subtype: TopicSubtype.system_message,
        target_usernames: user.username,
        skip_validations: true,
      )
    end

    def extract_title_from_markdown(raw)
      match = raw.match(/^#\s+(.+)$/)
      match ? match[1].strip : nil
    end
  end
end
