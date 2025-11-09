# frozen_string_literal: true

class AddOrdinalToLotteryPackets < ActiveRecord::Migration[7.0]
  def up
    # Add ordinal column (nullable first for backfill)
    add_column :vzekc_verlosung_lottery_packets, :ordinal, :integer, null: true

    # Backfill ordinal for existing packets based on post_number within each lottery
    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packets
      SET ordinal = ranked.row_num
      FROM (
        SELECT
          vp.id,
          ROW_NUMBER() OVER (PARTITION BY vp.lottery_id ORDER BY p.post_number) as row_num
        FROM vzekc_verlosung_lottery_packets vp
        INNER JOIN posts p ON p.id = vp.post_id
      ) AS ranked
      WHERE vzekc_verlosung_lottery_packets.id = ranked.id
    SQL

    # Make it NOT NULL now that we've backfilled
    change_column_null :vzekc_verlosung_lottery_packets, :ordinal, false
  end

  def down
    remove_column :vzekc_verlosung_lottery_packets, :ordinal
  end
end
