# frozen_string_literal: true

module Jobs
  class VzekcVerlosungErhaltungsberichtReminder < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled
      return if SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id.blank?

      # Find all winner entries that are collected but missing Erhaltungsberichte
      VzekcVerlosung::LotteryPacketWinner
        .collected
        .without_report
        .requiring_report
        .joins(lottery_packet: { lottery: :topic })
        .includes(:winner, lottery_packet: [:post, { lottery: :topic }])
        .where(vzekc_verlosung_lotteries: { state: "finished" })
        .where.not(vzekc_verlosung_lotteries: { drawn_at: nil })
        .find_each do |winner_entry|
          next if winner_entry.collected_at.blank?

          # Calculate days since collection
          days_since_collected = (Time.zone.now - winner_entry.collected_at).to_i / 1.day

          # Only send reminder every 7 days (on days 7, 14, 21, etc.)
          next if (days_since_collected % 7).nonzero? || days_since_collected <= 0

          # Get winner and packet info
          winner = winner_entry.winner
          next unless winner

          packet = winner_entry.lottery_packet
          lottery = packet.lottery
          packet_post = packet.post

          # Build packet title with instance number for multi-instance packets
          packet_title =
            VzekcVerlosung::TitleExtractor.extract_title(packet_post.raw) ||
              "Paket ##{packet_post.post_number}"
          packet_title = "#{packet_title} (##{winner_entry.instance_number})" if packet.quantity > 1

          VzekcVerlosung::NotificationService.notify(
            :erhaltungsbericht_reminder,
            recipient: winner,
            context: {
              lottery_topic: lottery.topic,
              packet_post: packet_post,
              packet_title: packet_title,
              days_since_collected: days_since_collected,
            },
          )
        end
    end
  end
end
