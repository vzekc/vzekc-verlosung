# frozen_string_literal: true

class AddDonorContactToDonations < ActiveRecord::Migration[7.2]
  def up
    add_column :vzekc_verlosung_donations, :donor_name, :string
    add_column :vzekc_verlosung_donations, :donor_company, :string
    add_column :vzekc_verlosung_donations, :donor_email, :string
    add_column :vzekc_verlosung_donations, :closed_at, :datetime

    # Closed donations are closed at pickup, or manually by the facilitator
    execute <<~SQL
      UPDATE vzekc_verlosung_donations d
      SET closed_at = COALESCE(
        (SELECT MAX(o.picked_up_at) FROM vzekc_verlosung_pickup_offers o WHERE o.donation_id = d.id),
        d.updated_at
      )
      WHERE d.state = 'closed'
    SQL

    execute <<~SQL
      UPDATE vzekc_verlosung_donations d
      SET donor_name = p.donor_name, donor_company = p.donor_company, donor_email = p.donor_email
      FROM vzekc_verlosung_merch_packets p
      WHERE p.donation_id = d.id AND p.state <> 'archived'
    SQL
  end

  def down
    remove_column :vzekc_verlosung_donations, :donor_name
    remove_column :vzekc_verlosung_donations, :donor_company
    remove_column :vzekc_verlosung_donations, :donor_email
    remove_column :vzekc_verlosung_donations, :closed_at
  end
end
