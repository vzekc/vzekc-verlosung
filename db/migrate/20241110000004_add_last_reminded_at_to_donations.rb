# frozen_string_literal: true

class AddLastRemindedAtToDonations < ActiveRecord::Migration[7.0]
  def change
    add_column :vzekc_verlosung_donations, :last_reminded_at, :datetime
  end
end
