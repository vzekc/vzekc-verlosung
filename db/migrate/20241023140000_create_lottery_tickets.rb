# frozen_string_literal: true

class CreateLotteryTickets < ActiveRecord::Migration[7.0]
  def change
    create_table :vzekc_verlosung_lottery_tickets do |t|
      t.integer :post_id, null: false
      t.integer :user_id, null: false
      t.timestamps
    end

    add_index :vzekc_verlosung_lottery_tickets,
              %i[post_id user_id],
              unique: true,
              name: "index_lottery_tickets_on_post_and_user"
    add_index :vzekc_verlosung_lottery_tickets, :post_id
    add_index :vzekc_verlosung_lottery_tickets, :user_id
  end
end
