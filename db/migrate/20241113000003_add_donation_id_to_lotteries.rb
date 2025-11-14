# frozen_string_literal: true

class AddDonationIdToLotteries < ActiveRecord::Migration[7.1]
  def up
    add_column :vzekc_verlosung_lotteries, :donation_id, :bigint

    add_index :vzekc_verlosung_lotteries, :donation_id, unique: true

    add_foreign_key :vzekc_verlosung_lotteries,
                    :vzekc_verlosung_donations,
                    column: :donation_id,
                    on_delete: :nullify
  end

  def down
    remove_foreign_key :vzekc_verlosung_lotteries, column: :donation_id
    remove_index :vzekc_verlosung_lotteries, :donation_id
    remove_column :vzekc_verlosung_lotteries, :donation_id
  end
end
