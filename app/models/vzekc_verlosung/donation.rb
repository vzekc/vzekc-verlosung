# frozen_string_literal: true

module VzekcVerlosung
  # Model for donation offers
  #
  # @attr topic_id [Integer] Associated Discourse topic (set after topic creation)
  # @attr state [String] Current state: draft, open, assigned, picked_up, closed
  # @attr postcode [String] Location postcode for pickup
  # @attr creator_user_id [Integer] User who created the donation offer
  # @attr published_at [DateTime] When the donation was published (changed to 'open')
  #
  class Donation < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_donations"

    belongs_to :topic, optional: true
    belongs_to :creator, class_name: "User", foreign_key: :creator_user_id
    has_many :pickup_offers, dependent: :destroy

    validates :state, presence: true, inclusion: { in: %w[draft open assigned picked_up closed] }
    validates :postcode, presence: true
    validates :creator_user_id, presence: true

    # State scopes
    scope :draft, -> { where(state: "draft") }
    scope :open, -> { where(state: "open") }
    scope :assigned, -> { where(state: "assigned") }
    scope :picked_up, -> { where(state: "picked_up") }
    scope :closed, -> { where(state: "closed") }
    scope :needs_reminder,
          lambda {
            open.where("published_at IS NOT NULL").where(
              "last_reminded_at IS NULL OR last_reminded_at < ?",
              24.hours.ago,
            )
          }

    # State helper methods
    #
    # @return [Boolean] true if in draft state
    def draft?
      state == "draft"
    end

    # @return [Boolean] true if in open state
    def open?
      state == "open"
    end

    # @return [Boolean] true if in assigned state
    def assigned?
      state == "assigned"
    end

    # @return [Boolean] true if in picked_up state
    def picked_up?
      state == "picked_up"
    end

    # @return [Boolean] true if in closed state
    def closed?
      state == "closed"
    end

    # Publish the donation (draft → open)
    #
    # @return [Boolean] true if successful
    def publish!
      update!(state: "open", published_at: Time.zone.now)
    end

    # Assign donation to a specific pickup offer
    #
    # @param pickup_offer [PickupOffer] The offer to assign
    # @return [Boolean] true if successful
    def assign_to!(pickup_offer)
      transaction do
        update!(state: "assigned")
        # Mark the selected offer as assigned
        pickup_offer.update!(state: "assigned", assigned_at: Time.zone.now)
        # Keep other offers visible but in pending state for transparency
      end
    end

    # Mark donation as picked up
    #
    # @return [Boolean] true if successful
    def mark_picked_up!
      transaction do
        update!(state: "picked_up")
        # Update the assigned offer
        assigned_offer = pickup_offers.find_by(state: "assigned")
        assigned_offer&.update!(state: "picked_up", picked_up_at: Time.zone.now)
      end
      # Auto-close after pickup
      close_automatically!
    end

    # Close the donation
    #
    # @return [Boolean] true if successful
    def close!
      update!(state: "closed")
    end

    private

    # Automatically close donation after pickup
    def close_automatically!
      close! if picked_up?
    end
  end
end
