# frozen_string_literal: true

module VzekcVerlosung
  # Model for pickup offers on donations
  #
  # @attr donation_id [Integer] Associated donation
  # @attr user_id [Integer] User who offered to pick up
  # @attr state [String] Current state: pending, assigned, picked_up
  # @attr assigned_at [DateTime] When this offer was selected by the creator
  # @attr picked_up_at [DateTime] When pickup was confirmed
  # @attr notes [String] Optional notes from the user
  #
  class PickupOffer < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_pickup_offers"

    belongs_to :donation
    belongs_to :user

    validates :state, presence: true, inclusion: { in: %w[pending assigned picked_up] }
    validates :user_id, uniqueness: { scope: :donation_id }
    validates :donation_id, presence: true
    validates :user_id, presence: true

    # State scopes
    scope :pending, -> { where(state: "pending") }
    scope :assigned, -> { where(state: "assigned") }
    scope :picked_up, -> { where(state: "picked_up") }
    scope :active, -> { where(state: %w[pending assigned]) }

    # State helper methods
    #
    # @return [Boolean] true if in pending state
    def pending?
      state == "pending"
    end

    # @return [Boolean] true if in assigned state
    def assigned?
      state == "assigned"
    end

    # @return [Boolean] true if in picked_up state
    def picked_up?
      state == "picked_up"
    end

    # Retract this pickup offer by deleting it
    #
    # @return [Boolean] true if successful
    def retract!
      destroy!
    end
  end
end

# == Schema Information
#
# Table name: vzekc_verlosung_pickup_offers
#
#  id           :bigint           not null, primary key
#  assigned_at  :datetime
#  notes        :text
#  picked_up_at :datetime
#  state        :string           default("pending"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  donation_id  :integer          not null
#  user_id      :integer          not null
#
# Indexes
#
#  index_pickup_offers_on_donation_and_user            (donation_id,user_id) UNIQUE
#  index_vzekc_verlosung_pickup_offers_on_donation_id  (donation_id)
#  index_vzekc_verlosung_pickup_offers_on_state        (state)
#  index_vzekc_verlosung_pickup_offers_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (donation_id => vzekc_verlosung_donations.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
