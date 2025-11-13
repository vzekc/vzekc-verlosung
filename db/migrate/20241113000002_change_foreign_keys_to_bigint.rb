# frozen_string_literal: true

class ChangeForeignKeysToBigint < ActiveRecord::Migration[7.0]
  def up
    # Change all foreign keys that reference Discourse core tables from integer to bigint
    # This is necessary because Discourse uses bigint for primary keys, and in CI environments
    # the sequence can reach values > 2.1 billion (integer max), causing overflow errors

    # Lotteries table
    change_column :vzekc_verlosung_lotteries, :topic_id, :bigint, null: false

    # Lottery Packets table
    change_column :vzekc_verlosung_lottery_packets, :post_id, :bigint, null: false
    change_column :vzekc_verlosung_lottery_packets, :winner_user_id, :bigint
    change_column :vzekc_verlosung_lottery_packets, :erhaltungsbericht_topic_id, :bigint

    # Lottery Tickets table
    change_column :vzekc_verlosung_lottery_tickets, :post_id, :bigint, null: false
    change_column :vzekc_verlosung_lottery_tickets, :user_id, :bigint, null: false

    # Donations table
    change_column :vzekc_verlosung_donations, :topic_id, :bigint
    change_column :vzekc_verlosung_donations, :creator_user_id, :bigint, null: false

    # Pickup Offers table
    change_column :vzekc_verlosung_pickup_offers, :user_id, :bigint, null: false
  end

  def down
    # Revert to integer (only safe if no large IDs exist)
    change_column :vzekc_verlosung_lotteries, :topic_id, :integer, null: false

    change_column :vzekc_verlosung_lottery_packets, :post_id, :integer, null: false
    change_column :vzekc_verlosung_lottery_packets, :winner_user_id, :integer
    change_column :vzekc_verlosung_lottery_packets, :erhaltungsbericht_topic_id, :integer

    change_column :vzekc_verlosung_lottery_tickets, :post_id, :integer, null: false
    change_column :vzekc_verlosung_lottery_tickets, :user_id, :integer, null: false

    change_column :vzekc_verlosung_donations, :topic_id, :integer
    change_column :vzekc_verlosung_donations, :creator_user_id, :integer, null: false

    change_column :vzekc_verlosung_pickup_offers, :user_id, :integer, null: false
  end
end
