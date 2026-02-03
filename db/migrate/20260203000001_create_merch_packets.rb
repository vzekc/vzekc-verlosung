# frozen_string_literal: true

class CreateMerchPackets < ActiveRecord::Migration[7.2]
  def change
    create_table :vzekc_verlosung_merch_packets do |t|
      t.references :donation,
                   null: false,
                   index: { unique: true },
                   foreign_key: {
                     to_table: :vzekc_verlosung_donations,
                     on_delete: :cascade,
                   }
      # German postal address fields (nullable for anonymization after archival)
      t.string :donor_name
      t.string :donor_company
      t.string :donor_street
      t.string :donor_street_number
      t.string :donor_postcode
      t.string :donor_city
      t.string :donor_email
      # Fulfillment tracking
      t.string :state, null: false, default: "pending"
      t.text :tracking_info
      t.datetime :shipped_at
      t.references :shipped_by_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    add_index :vzekc_verlosung_merch_packets, :state
    add_index :vzekc_verlosung_merch_packets, %i[state shipped_at], name: "idx_merch_packets_for_archival"
  end
end
