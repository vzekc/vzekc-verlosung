# frozen_string_literal: true

class AddForeignKeysToLotteryTickets < ActiveRecord::Migration[7.0]
  def change
    # Add foreign key to posts table with cascade delete
    # When a post is deleted, all tickets for that post should be deleted
    add_foreign_key :vzekc_verlosung_lottery_tickets, :posts, on_delete: :cascade

    # Add foreign key to users table with cascade delete
    # When a user is deleted, all their tickets should be deleted
    add_foreign_key :vzekc_verlosung_lottery_tickets, :users, on_delete: :cascade
  end
end
