# frozen_string_literal: true

class AddTitleAndMakeDonationOptionalOnMerchPackets < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_merch_packets, :title, :string

    change_column_null :vzekc_verlosung_merch_packets, :donation_id, true

    remove_index :vzekc_verlosung_merch_packets,
                 :donation_id,
                 unique: true,
                 name: "index_vzekc_verlosung_merch_packets_on_donation_id"

    add_index :vzekc_verlosung_merch_packets,
              :donation_id,
              unique: true,
              where: "donation_id IS NOT NULL",
              name: "index_vzekc_verlosung_merch_packets_on_donation_id"
  end
end
