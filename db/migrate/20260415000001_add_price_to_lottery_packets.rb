# frozen_string_literal: true

class AddPriceToLotteryPackets < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lottery_packets, :price_cents, :integer, null: true
    add_column :vzekc_verlosung_lottery_packets, :price_reason, :text, null: true
  end
end
