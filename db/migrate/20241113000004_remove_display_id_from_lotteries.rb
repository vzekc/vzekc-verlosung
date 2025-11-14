# frozen_string_literal: true

class RemoveDisplayIdFromLotteries < ActiveRecord::Migration[7.1]
  def up
    remove_index :vzekc_verlosung_lotteries, :display_id
    remove_column :vzekc_verlosung_lotteries, :display_id
  end

  def down
    add_column :vzekc_verlosung_lotteries, :display_id, :integer, null: false
    add_index :vzekc_verlosung_lotteries, :display_id, unique: true
  end
end
