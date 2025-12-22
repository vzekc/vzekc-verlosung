# frozen_string_literal: true

class MigrateExistingWinners < ActiveRecord::Migration[7.2]
  def up
    # Migrate winner data from lottery_packets to new junction table
    execute <<~SQL
      INSERT INTO vzekc_verlosung_lottery_packet_winners
        (lottery_packet_id, winner_user_id, instance_number, won_at,
         collected_at, erhaltungsbericht_topic_id, created_at, updated_at)
      SELECT
        id, winner_user_id, 1, won_at,
        collected_at, erhaltungsbericht_topic_id, NOW(), NOW()
      FROM vzekc_verlosung_lottery_packets
      WHERE winner_user_id IS NOT NULL
    SQL

    # Transform results JSON: convert "winner" to "winners" array format
    # Also add "quantity": 1 to each drawing for consistency
    execute <<~SQL
      UPDATE vzekc_verlosung_lotteries
      SET results = (
        SELECT jsonb_set(
          results,
          '{drawings}',
          (
            SELECT jsonb_agg(
              CASE
                WHEN drawing ? 'winner' AND NOT (drawing ? 'winners') THEN
                  jsonb_set(
                    jsonb_set(
                      drawing - 'winner',
                      '{winners}',
                      CASE
                        WHEN drawing->>'winner' IS NOT NULL THEN
                          jsonb_build_array(drawing->>'winner')
                        ELSE
                          '[]'::jsonb
                      END
                    ),
                    '{quantity}',
                    '1'::jsonb
                  )
                ELSE
                  drawing
              END
            )
            FROM jsonb_array_elements(results->'drawings') AS drawing
          )
        )
      )
      WHERE results IS NOT NULL
        AND results ? 'drawings'
        AND EXISTS (
          SELECT 1
          FROM jsonb_array_elements(results->'drawings') AS d
          WHERE d ? 'winner' AND NOT (d ? 'winners')
        )
    SQL
  end

  def down
    # Restore winner data to lottery_packets from junction table
    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packets lp
      SET
        winner_user_id = lpw.winner_user_id,
        won_at = lpw.won_at,
        collected_at = lpw.collected_at,
        erhaltungsbericht_topic_id = lpw.erhaltungsbericht_topic_id
      FROM vzekc_verlosung_lottery_packet_winners lpw
      WHERE lpw.lottery_packet_id = lp.id
        AND lpw.instance_number = 1
    SQL

    execute "DELETE FROM vzekc_verlosung_lottery_packet_winners"

    # Transform results JSON back: convert "winners" array to single "winner"
    execute <<~SQL
      UPDATE vzekc_verlosung_lotteries
      SET results = (
        SELECT jsonb_set(
          results,
          '{drawings}',
          (
            SELECT jsonb_agg(
              CASE
                WHEN drawing ? 'winners' THEN
                  jsonb_set(
                    drawing - 'winners' - 'quantity',
                    '{winner}',
                    CASE
                      WHEN jsonb_array_length(drawing->'winners') > 0 THEN
                        drawing->'winners'->0
                      ELSE
                        'null'::jsonb
                    END
                  )
                ELSE
                  drawing
              END
            )
            FROM jsonb_array_elements(results->'drawings') AS drawing
          )
        )
      )
      WHERE results IS NOT NULL
        AND results ? 'drawings'
        AND EXISTS (
          SELECT 1
          FROM jsonb_array_elements(results->'drawings') AS d
          WHERE d ? 'winners'
        )
    SQL
  end
end
