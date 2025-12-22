# frozen_string_literal: true

class AddQuantityToLotteryPackets < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lottery_packets, :quantity, :integer, default: 1, null: false
  end
end
