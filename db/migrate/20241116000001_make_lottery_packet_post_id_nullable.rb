# frozen_string_literal: true

class MakeLotteryPacketPostIdNullable < ActiveRecord::Migration[7.0]
  def up
    # Make post_id nullable for Abholerpakete (which won't have associated posts)
    change_column_null :vzekc_verlosung_lottery_packets, :post_id, true
  end

  def down
    # Reverse migration - make post_id not null again
    # First, delete any packets without post_id (should only be Abholerpakete)
    execute <<-SQL
      DELETE FROM vzekc_verlosung_lottery_packets
      WHERE post_id IS NULL
    SQL

    change_column_null :vzekc_verlosung_lottery_packets, :post_id, false
  end
end
