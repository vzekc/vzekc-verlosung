# frozen_string_literal: true

class CreateLotteryTables < ActiveRecord::Migration[7.0]
  def change
    # Lotteries table - one per lottery topic
    create_table :vzekc_verlosung_lotteries do |t|
      t.integer :topic_id, null: false
      t.string :state, null: false, default: "draft"
      t.integer :duration_days
      t.datetime :ends_at
      t.datetime :drawn_at
      t.jsonb :results
      t.timestamps
    end

    add_index :vzekc_verlosung_lotteries, :topic_id, unique: true
    add_index :vzekc_verlosung_lotteries, :state
    add_index :vzekc_verlosung_lotteries,
              %i[state ends_at],
              name: "index_lotteries_on_state_and_ends_at"

    add_foreign_key :vzekc_verlosung_lotteries, :topics, on_delete: :cascade

    # Lottery packets table - one per packet post
    create_table :vzekc_verlosung_lottery_packets do |t|
      t.integer :lottery_id, null: false
      t.integer :post_id, null: false
      t.string :title, null: false
      t.integer :winner_user_id
      t.datetime :won_at
      t.datetime :collected_at
      t.integer :erhaltungsbericht_topic_id
      t.timestamps
    end

    add_index :vzekc_verlosung_lottery_packets, :post_id, unique: true
    add_index :vzekc_verlosung_lottery_packets, :lottery_id
    add_index :vzekc_verlosung_lottery_packets, :winner_user_id
    add_index :vzekc_verlosung_lottery_packets,
              %i[collected_at winner_user_id],
              name: "index_packets_on_collected_and_winner",
              where: "winner_user_id IS NOT NULL AND collected_at IS NULL"

    add_foreign_key :vzekc_verlosung_lottery_packets,
                    :vzekc_verlosung_lotteries,
                    column: :lottery_id,
                    on_delete: :cascade
    add_foreign_key :vzekc_verlosung_lottery_packets, :posts, on_delete: :cascade
    add_foreign_key :vzekc_verlosung_lottery_packets,
                    :users,
                    column: :winner_user_id,
                    on_delete: :nullify
    add_foreign_key :vzekc_verlosung_lottery_packets,
                    :topics,
                    column: :erhaltungsbericht_topic_id,
                    on_delete: :nullify
  end
end
