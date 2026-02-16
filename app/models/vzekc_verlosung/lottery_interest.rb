# frozen_string_literal: true

module VzekcVerlosung
  # Model for lottery interest expressions on donations
  #
  # @attr donation_id [Integer] Associated donation
  # @attr user_id [Integer] User who expressed interest in a potential lottery
  #
  class LotteryInterest < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_lottery_interests"

    belongs_to :donation
    belongs_to :user

    validates :user_id, uniqueness: { scope: :donation_id }
    validates :donation_id, presence: true
    validates :user_id, presence: true
  end
end

# == Schema Information
#
# Table name: vzekc_verlosung_lottery_interests
#
#  id          :bigint           not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  donation_id :bigint           not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_lottery_interests_on_donation_and_user            (donation_id,user_id) UNIQUE
#  index_vzekc_verlosung_lottery_interests_on_donation_id  (donation_id)
#  index_vzekc_verlosung_lottery_interests_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (donation_id => vzekc_verlosung_donations.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
