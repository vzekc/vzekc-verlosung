# frozen_string_literal: true

class AddAbholerpaketToLotteryPackets < ActiveRecord::Migration[7.0]
  def change
    add_column :vzekc_verlosung_lottery_packets,
               :abholerpaket,
               :boolean,
               null: false,
               default: false
  end
end
