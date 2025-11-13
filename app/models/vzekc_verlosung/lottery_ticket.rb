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

    # Helper to get the associated lottery packet
    def lottery_packet
      VzekcVerlosung::LotteryPacket.find_by(post_id: post_id)
    end
  end
end

# == Schema Information
#
# Table name: vzekc_verlosung_lottery_tickets
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  post_id    :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_lottery_tickets_on_post_and_user            (post_id,user_id) UNIQUE
#  index_vzekc_verlosung_lottery_tickets_on_post_id  (post_id)
#  index_vzekc_verlosung_lottery_tickets_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (post_id => posts.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
