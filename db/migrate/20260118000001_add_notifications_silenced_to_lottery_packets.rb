# frozen_string_literal: true

class AddNotificationsSilencedToLotteryPackets < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lottery_packets, :notifications_silenced, :boolean, default: false, null: false
  end
end
