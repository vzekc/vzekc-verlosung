# frozen_string_literal: true

class ChangeDisplayIdToInteger < ActiveRecord::Migration[7.0]
  def up
    # Change display_id from bigint to integer
    # Safe because production values will never exceed 2.1 billion
    # and test fabricator now uses modulo wrapping to stay in range
    change_column :vzekc_verlosung_lotteries, :display_id, :integer, null: false
  end

  def down
    change_column :vzekc_verlosung_lotteries, :display_id, :bigint, null: false
  end
end
