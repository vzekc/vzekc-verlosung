# frozen_string_literal: true

class AddNoteToLotteryPackets < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lottery_packets, :note, :text, null: true
  end
end
