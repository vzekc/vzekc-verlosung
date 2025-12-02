# frozen_string_literal: true

class RemoveDraftStateFromLotteries < ActiveRecord::Migration[7.0]
  def up
    # Delete all draft lotteries and their associated data
    execute <<~SQL
      DELETE FROM vzekc_verlosung_lottery_packets
      WHERE lottery_id IN (
        SELECT id FROM vzekc_verlosung_lotteries WHERE state = 'draft'
      )
    SQL

    execute <<~SQL
      DELETE FROM vzekc_verlosung_lotteries WHERE state = 'draft'
    SQL

    # Add check constraint to only allow 'active' and 'finished' states
    execute <<~SQL
      ALTER TABLE vzekc_verlosung_lotteries
      ADD CONSTRAINT check_lottery_state
      CHECK (state IN ('active', 'finished'))
    SQL
  end

  def down
    # Remove the check constraint
    execute <<~SQL
      ALTER TABLE vzekc_verlosung_lotteries
      DROP CONSTRAINT IF EXISTS check_lottery_state
    SQL

    # Note: Cannot restore deleted draft lotteries
  end
end
