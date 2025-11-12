# frozen_string_literal: true

# Migration to create the donations table for managing donation offers
class CreateDonations < ActiveRecord::Migration[7.1]
  def up
    create_table :vzekc_verlosung_donations do |t|
      t.integer :topic_id # nullable initially, set via topic_created hook
      t.string :state, null: false, default: "draft"
      t.string :postcode, null: false
      t.integer :creator_user_id, null: false
      t.datetime :published_at # when changed to 'open' state
      t.timestamps
    end

    add_index :vzekc_verlosung_donations, :topic_id, unique: true
    add_index :vzekc_verlosung_donations, :state
    add_index :vzekc_verlosung_donations, :creator_user_id
    add_index :vzekc_verlosung_donations, %i[state published_at]

    add_foreign_key :vzekc_verlosung_donations, :topics, on_delete: :cascade
    add_foreign_key :vzekc_verlosung_donations,
                    :users,
                    column: :creator_user_id,
                    on_delete: :cascade
  end

  def down
    drop_table :vzekc_verlosung_donations
  end
end
