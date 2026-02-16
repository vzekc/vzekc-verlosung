# frozen_string_literal: true

class AddOwnerRemindersSilencedToLotteries < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lotteries,
               :owner_reminders_silenced,
               :boolean,
               default: false,
               null: false
  end
end
