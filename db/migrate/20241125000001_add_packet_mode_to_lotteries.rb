# frozen_string_literal: true

class AddPacketModeToLotteries < ActiveRecord::Migration[7.0]
  def change
    add_column :vzekc_verlosung_lotteries, :packet_mode, :string, default: "mehrere", null: false
    add_index :vzekc_verlosung_lotteries, :packet_mode
  end
end
