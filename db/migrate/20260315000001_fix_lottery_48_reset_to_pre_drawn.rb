# frozen_string_literal: true

class FixLottery48ResetToPreDrawn < ActiveRecord::Migration[7.2]
  def up
    # Lottery 48 (topic 922) was drawn on 2026-03-15 but the drawing failed
    # halfway through due to a unique constraint violation on packet 286.
    # The lottery was left in a broken state: marked finished with results JSON,
    # but zero drawing winners written to the database.
    #
    # This migration resets the lottery to a pre-drawn state so the owner can
    # re-draw it cleanly.

    # Step 1: Remove Toshi's conflicting winner record on packet 286
    execute <<~SQL
      DELETE FROM vzekc_verlosung_lottery_packet_winners
      WHERE id = 205
        AND lottery_packet_id = 286
        AND winner_user_id = 656
        AND instance_number = 1
    SQL

    # Step 2: Reset packet 286 state back to pending
    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packets
      SET state = 'pending'
      WHERE id = 286
        AND state = 'drawn'
    SQL

    # Step 3: Reset lottery 48 to active state
    # ends_at is left unchanged — the lottery's participation period already
    # ended, so the UI will correctly show "Wartet auf Ziehung" with the
    # draw button available to the owner.
    execute <<~SQL
      UPDATE vzekc_verlosung_lotteries
      SET state = 'active',
          drawn_at = NULL,
          results = NULL
      WHERE id = 48
        AND state = 'finished'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
