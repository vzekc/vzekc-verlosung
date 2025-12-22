# frozen_string_literal: true

class AddTrackingInfoToLotteryPacketWinners < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lottery_packet_winners, :tracking_info, :text, null: true
  end
end
