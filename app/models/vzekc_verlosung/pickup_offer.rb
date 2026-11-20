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

    # Pickups older than this do not count towards the pickup balance.
    BALANCE_WINDOW = 24.months

    # Points each pickup outcome contributes to the pickup balance. Passing a
    # donation on through a lottery lowers the balance, which makes the picker
    # preferred by auto-assignment; keeping it raises the balance. A pickup
    # without an outcome yet counts as kept until the picker decides.
    BALANCE_POINTS = { kept: 1, pending: 1, partial: 0, passed_on: -1 }.freeze

    # Pickup statistics for the given users over the last BALANCE_WINDOW.
    #
    # Each picked-up donation falls into one outcome:
    # - :kept — the picker wrote an Erhaltungsbericht
    # - :passed_on — raffled in a lottery without Abholerpaket or at an onsite lottery event
    # - :partial — raffled in a lottery in which the picker kept an Abholerpaket
    # - :pending — no outcome yet
    #
    # @param user_ids [Array<Integer>] the users to compute statistics for
    # @return [Hash{Integer => Hash}] per user id: counts for each outcome
    #   (:kept, :passed_on, :partial, :pending) and the resulting :balance
    def self.pickup_stats(user_ids)
      user_ids = Array(user_ids).uniq
      stats = user_ids.index_with { BALANCE_POINTS.keys.index_with(0).merge(balance: 0) }
      return stats if user_ids.empty?

      offers =
        picked_up
          .where(user_id: user_ids)
          .where("COALESCE(picked_up_at, assigned_at, created_at) >= ?", BALANCE_WINDOW.ago)
          .includes(donation: :lottery)
          .to_a

      lottery_ids = offers.filter_map { |offer| offer.donation&.lottery&.id }
      lotteries_with_abholerpaket =
        LotteryPacket.where(lottery_id: lottery_ids, abholerpaket: true).distinct.pluck(:lottery_id)

      offers.each do |offer|
        outcome = pickup_outcome(offer.donation, lotteries_with_abholerpaket)
        entry = stats[offer.user_id]
        entry[outcome] += 1
        entry[:balance] += BALANCE_POINTS[outcome]
      end

      stats
    end

    # Pickup statistics for a single user, see .pickup_stats
    #
    # @param user_id [Integer]
    # @return [Hash]
    def self.pickup_stats_for(user_id)
      pickup_stats([user_id])[user_id]
    end

    # @param donation [Donation, nil]
    # @param lotteries_with_abholerpaket [Array<Integer>] ids of lotteries with an Abholerpaket
    # @return [Symbol] one of BALANCE_POINTS' keys
    def self.pickup_outcome(donation, lotteries_with_abholerpaket)
      return :pending unless donation
      return :kept if donation.erhaltungsbericht_topic_id.present?
      return :passed_on if donation.onsite_lottery_event_id.present?

      lottery = donation.lottery
      return :pending unless lottery

      lotteries_with_abholerpaket.include?(lottery.id) ? :partial : :passed_on
    end
    private_class_method :pickup_outcome

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
#  donation_id  :bigint           not null
#  user_id      :bigint           not null
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
