# frozen_string_literal: true

class AddDrawingModeToLotteries < ActiveRecord::Migration[7.1]
  def up
    add_column :vzekc_verlosung_lotteries, :drawing_mode, :string, default: "automatic", null: false
  end

  def down
    remove_column :vzekc_verlosung_lotteries, :drawing_mode
  end
end
