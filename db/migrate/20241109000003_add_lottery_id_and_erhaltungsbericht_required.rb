# frozen_string_literal: true

class AddLotteryIdAndErhaltungsberichtRequired < ActiveRecord::Migration[7.0]
  def up
    # Add display_id as nullable first
    add_column :vzekc_verlosung_lotteries, :display_id, :integer, null: true

    # Backfill existing lotteries with sequential display_ids starting from 401
    execute <<~SQL
      UPDATE vzekc_verlosung_lotteries
      SET display_id = 400 + row_number
      FROM (
        SELECT id, ROW_NUMBER() OVER (ORDER BY id) as row_number
        FROM vzekc_verlosung_lotteries
      ) AS numbered
      WHERE vzekc_verlosung_lotteries.id = numbered.id
    SQL

    # Now make it NOT NULL and add unique index
    change_column_null :vzekc_verlosung_lotteries, :display_id, false
    add_index :vzekc_verlosung_lotteries, :display_id, unique: true

    # Add erhaltungsbericht_required to lottery_packets table
    add_column :vzekc_verlosung_lottery_packets,
               :erhaltungsbericht_required,
               :boolean,
               null: false,
               default: true
  end

  def down
    remove_index :vzekc_verlosung_lotteries, :display_id
    remove_column :vzekc_verlosung_lotteries, :display_id
    remove_column :vzekc_verlosung_lottery_packets, :erhaltungsbericht_required
  end
end
