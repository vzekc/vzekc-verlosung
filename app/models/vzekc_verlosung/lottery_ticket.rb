# frozen_string_literal: true

module VzekcVerlosung
  # Represents a lottery ticket for a specific post/packet
  class LotteryTicket < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_lottery_tickets"

    belongs_to :post
    belongs_to :user

    validates :post_id, presence: true
    validates :user_id, presence: true
    validates :post_id, uniqueness: { scope: :user_id }
  end
end
