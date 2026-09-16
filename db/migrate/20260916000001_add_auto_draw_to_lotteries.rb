# frozen_string_literal: true

class AddAutoDrawToLotteries < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lotteries, :auto_draw, :boolean, default: false, null: false
  end
end
