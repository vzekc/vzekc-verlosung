# frozen_string_literal: true

class AddOnsiteLotteryEventToDonations < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_donations, :onsite_lottery_event_id, :bigint
    add_index :vzekc_verlosung_donations, :onsite_lottery_event_id
    add_foreign_key :vzekc_verlosung_donations,
                    :vzekc_verlosung_onsite_lottery_events,
                    column: :onsite_lottery_event_id,
                    on_delete: :nullify
  end
end
