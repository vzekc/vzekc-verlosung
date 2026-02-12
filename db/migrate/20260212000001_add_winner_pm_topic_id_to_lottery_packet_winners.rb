# frozen_string_literal: true

class AddWinnerPmTopicIdToLotteryPacketWinners < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lottery_packet_winners, :winner_pm_topic_id, :bigint, null: true

    add_foreign_key :vzekc_verlosung_lottery_packet_winners,
                    :topics,
                    column: :winner_pm_topic_id,
                    on_delete: :nullify

    reversible do |dir|
      dir.up do
        # Backfill existing winner PM topic IDs by matching PMs heuristically:
        # - Title matches the winner PM format
        # - First post authored by the lottery owner
        # - First post body starts with "Hallo <username>,"
        # Verified against production data: 166/166 matches
        execute <<~SQL
          UPDATE vzekc_verlosung_lottery_packet_winners lpw
          SET winner_pm_topic_id = matched.pm_topic_id
          FROM (
            SELECT DISTINCT ON (lpw2.id) lpw2.id AS winner_id, t.id AS pm_topic_id
            FROM vzekc_verlosung_lottery_packet_winners lpw2
            JOIN vzekc_verlosung_lottery_packets lp ON lp.id = lpw2.lottery_packet_id
            JOIN vzekc_verlosung_lotteries l ON l.id = lp.lottery_id
            JOIN topics lt ON lt.id = l.topic_id
            JOIN users u ON u.id = lpw2.winner_user_id
            JOIN topics t ON t.archetype = 'private_message'
              AND t.title = 'Glückwunsch! Du hast in der Verlosung gewonnen: ' || lt.title
            JOIN posts p ON p.topic_id = t.id AND p.post_number = 1
              AND p.user_id = lt.user_id
              AND p.raw LIKE 'Hallo ' || u.username || ',%'
            ORDER BY lpw2.id, t.created_at
          ) matched
          WHERE lpw.id = matched.winner_id
        SQL
      end
    end
  end
end
