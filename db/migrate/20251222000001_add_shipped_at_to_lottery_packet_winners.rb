# frozen_string_literal: true

class AddShippedAtToLotteryPacketWinners < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lottery_packet_winners, :shipped_at, :datetime, null: true
  end
end
