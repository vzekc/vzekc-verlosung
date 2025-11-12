# frozen_string_literal: true

# Migration to create the pickup_offers table for tracking who wants to pick up donations
class CreatePickupOffers < ActiveRecord::Migration[7.1]
  def up
    create_table :vzekc_verlosung_pickup_offers do |t|
      t.integer :donation_id, null: false
      t.integer :user_id, null: false
      t.string :state, null: false, default: "pending"
      t.datetime :assigned_at
      t.datetime :picked_up_at
      t.text :notes
      t.timestamps
    end

    add_index :vzekc_verlosung_pickup_offers,
              %i[donation_id user_id],
              unique: true,
              name: "index_pickup_offers_on_donation_and_user"
    add_index :vzekc_verlosung_pickup_offers, :donation_id
    add_index :vzekc_verlosung_pickup_offers, :user_id
    add_index :vzekc_verlosung_pickup_offers, :state

    add_foreign_key :vzekc_verlosung_pickup_offers,
                    :vzekc_verlosung_donations,
                    column: :donation_id,
                    on_delete: :cascade
    add_foreign_key :vzekc_verlosung_pickup_offers, :users, on_delete: :cascade
  end

  def down
    drop_table :vzekc_verlosung_pickup_offers
  end
end
