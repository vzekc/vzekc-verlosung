# frozen_string_literal: true

module Jobs
  class VzekcVerlosungErhaltungsberichtReminder < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled
      return if SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id.blank?

      # Find all finished lotteries with drawn results
      VzekcVerlosung::Lottery
        .finished
        .where.not(drawn_at: nil)
        .includes(:lottery_packets)
        .find_each do |lottery|
          # Check each packet for missing Erhaltungsberichte
          lottery
            .lottery_packets
            .collected
            .without_report
            .includes(:winner, :post, :lottery)
            .each do |packet|
              next if packet.collected_at.blank?

              # Calculate days since collection
              days_since_collected = (Time.zone.now - packet.collected_at).to_i / 1.day

              # Only send reminder every 7 days (on days 7, 14, 21, etc.)
              next if (days_since_collected % 7).nonzero? || days_since_collected <= 0

              # Find the winner user
              winner = packet.winner
              next unless winner

              # Send reminder
              send_erhaltungsbericht_reminder(
                winner,
                lottery.topic,
                packet.post,
                days_since_collected,
              )
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
