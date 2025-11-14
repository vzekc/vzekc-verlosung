# frozen_string_literal: true

class ChangeForeignKeysToBigint < ActiveRecord::Migration[7.0]
  def up
    # Change ALL foreign keys from integer to bigint
    # This is necessary because:
    # 1. Discourse core tables (posts, topics, users) use bigint for primary keys
    # 2. Rails uses bigint by default for create_table, so plugin tables also have bigint PKs
    # 3. In CI, the global ID sequence can reach 10+ billion after running full Discourse suite
    # 4. Storing bigint IDs in integer columns causes overflow (max ~2.1 billion)

    # Lotteries table - references Discourse core
    change_column :vzekc_verlosung_lotteries, :topic_id, :bigint, null: false

    # Lottery Packets table - references both Discourse core AND plugin tables
    change_column :vzekc_verlosung_lottery_packets, :lottery_id, :bigint, null: false
    change_column :vzekc_verlosung_lottery_packets, :post_id, :bigint, null: false
    change_column :vzekc_verlosung_lottery_packets, :winner_user_id, :bigint
    change_column :vzekc_verlosung_lottery_packets, :erhaltungsbericht_topic_id, :bigint

    # Lottery Tickets table - references Discourse core
    change_column :vzekc_verlosung_lottery_tickets, :post_id, :bigint, null: false
    change_column :vzekc_verlosung_lottery_tickets, :user_id, :bigint, null: false

    # Donations table - references Discourse core
    change_column :vzekc_verlosung_donations, :topic_id, :bigint
    change_column :vzekc_verlosung_donations, :creator_user_id, :bigint, null: false

    # Pickup Offers table - references both Discourse core AND plugin tables
    change_column :vzekc_verlosung_pickup_offers, :donation_id, :bigint, null: false
    change_column :vzekc_verlosung_pickup_offers, :user_id, :bigint, null: false
  end

  def down
    # Revert to integer (only safe if no large IDs exist)
    change_column :vzekc_verlosung_lotteries, :topic_id, :integer, null: false

    change_column :vzekc_verlosung_lottery_packets, :lottery_id, :integer, null: false
    change_column :vzekc_verlosung_lottery_packets, :post_id, :integer, null: false
    change_column :vzekc_verlosung_lottery_packets, :winner_user_id, :integer
    change_column :vzekc_verlosung_lottery_packets, :erhaltungsbericht_topic_id, :integer

    change_column :vzekc_verlosung_lottery_tickets, :post_id, :integer, null: false
    change_column :vzekc_verlosung_lottery_tickets, :user_id, :integer, null: false

    change_column :vzekc_verlosung_donations, :topic_id, :integer
    change_column :vzekc_verlosung_donations, :creator_user_id, :integer, null: false

    change_column :vzekc_verlosung_pickup_offers, :donation_id, :integer, null: false
    change_column :vzekc_verlosung_pickup_offers, :user_id, :integer, null: false
  end
end
