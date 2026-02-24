# frozen_string_literal: true

class CreateOnsiteLotteryEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :vzekc_verlosung_onsite_lottery_events do |t|
      t.string :name, null: false
      t.date :event_date, null: false
      t.bigint :created_by_user_id, null: false
      t.datetime :last_reminded_at
      t.timestamps
    end

    add_index :vzekc_verlosung_onsite_lottery_events, :event_date
    add_foreign_key :vzekc_verlosung_onsite_lottery_events,
                    :users,
                    column: :created_by_user_id,
                    on_delete: :cascade
  end
end
