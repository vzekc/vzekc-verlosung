# frozen_string_literal: true

class CreateLotteryPacketWinners < ActiveRecord::Migration[7.2]
  def change
    create_table :vzekc_verlosung_lottery_packet_winners do |t|
      t.bigint :lottery_packet_id, null: false
      t.bigint :winner_user_id, null: false
      t.integer :instance_number, null: false
      t.datetime :won_at
      t.datetime :collected_at
      t.bigint :erhaltungsbericht_topic_id
      t.timestamps
    end

    add_index :vzekc_verlosung_lottery_packet_winners,
              :lottery_packet_id,
              name: "idx_lottery_packet_winners_on_packet_id"

    add_index :vzekc_verlosung_lottery_packet_winners,
              :winner_user_id,
              name: "idx_lottery_packet_winners_on_user_id"

    add_index :vzekc_verlosung_lottery_packet_winners,
              %i[lottery_packet_id instance_number],
              unique: true,
              name: "idx_lottery_packet_winners_unique_instance"

    add_index :vzekc_verlosung_lottery_packet_winners,
              %i[lottery_packet_id winner_user_id],
              unique: true,
              name: "idx_lottery_packet_winners_unique_user"

    add_foreign_key :vzekc_verlosung_lottery_packet_winners,
                    :vzekc_verlosung_lottery_packets,
                    column: :lottery_packet_id,
                    on_delete: :cascade

    add_foreign_key :vzekc_verlosung_lottery_packet_winners,
                    :users,
                    column: :winner_user_id,
                    on_delete: :cascade

    add_foreign_key :vzekc_verlosung_lottery_packet_winners,
                    :topics,
                    column: :erhaltungsbericht_topic_id,
                    on_delete: :nullify
  end
end
