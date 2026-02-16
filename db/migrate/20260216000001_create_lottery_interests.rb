# frozen_string_literal: true

# Migration to create the lottery_interests table for tracking users interested in a potential lottery
class CreateLotteryInterests < ActiveRecord::Migration[7.1]
  def up
    create_table :vzekc_verlosung_lottery_interests do |t|
      t.bigint :donation_id, null: false
      t.bigint :user_id, null: false
      t.timestamps
    end

    add_index :vzekc_verlosung_lottery_interests,
              %i[donation_id user_id],
              unique: true,
              name: "index_lottery_interests_on_donation_and_user"
    add_index :vzekc_verlosung_lottery_interests, :donation_id
    add_index :vzekc_verlosung_lottery_interests, :user_id

    add_foreign_key :vzekc_verlosung_lottery_interests,
                    :vzekc_verlosung_donations,
                    column: :donation_id,
                    on_delete: :cascade
    add_foreign_key :vzekc_verlosung_lottery_interests, :users, on_delete: :cascade
  end

  def down
    drop_table :vzekc_verlosung_lottery_interests
  end
end
