# frozen_string_literal: true

class AddUnclaimedAtToLotteryPacketWinners < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lottery_packet_winners, :unclaimed_at, :datetime, null: true
  end
end
