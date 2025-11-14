# frozen_string_literal: true

module VzekcVerlosung
  # Model for donation offers
  #
  # Roles:
  # - donor: Person who has hardware to give away (not in system)
  # - facilitator: User who creates donation offer, finds picker, provides donor contact (creator_user_id)
  # - picker: User who picks up donation, then keeps it or creates lottery
  #
  # @attr topic_id [Integer] Associated Discourse topic (set after topic creation)
  # @attr state [String] Current state: draft, open, assigned, picked_up, closed
  # @attr postcode [String] Location postcode for pickup
  # @attr creator_user_id [Integer] The facilitator who created the donation offer
  # @attr published_at [DateTime] When the donation was published (changed to 'open')
  #
  class Donation < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_donations"

    belongs_to :topic, optional: true
    belongs_to :facilitator, class_name: "User", foreign_key: :creator_user_id
    # Alias for backwards compatibility
    alias_method :creator, :facilitator
    has_many :pickup_offers, dependent: :destroy
    has_one :lottery, class_name: "VzekcVerlosung::Lottery", dependent: :nullify

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
    scope :needs_pickup_action_reminder,
          lambda {
            where(state: %w[picked_up closed]).where(
              "last_reminded_at IS NULL OR last_reminded_at < ?",
              7.days.ago,
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
    # @param contact_info [String] Contact information from donation creator
    # @return [Boolean] true if successful
    def assign_to!(pickup_offer, contact_info: nil)
      transaction do
        update!(state: "assigned")
        # Mark the selected offer as assigned
        pickup_offer.update!(state: "assigned", assigned_at: Time.zone.now)
        # Keep other offers visible but in pending state for transparency
      end
      # Send notification PM to assigned user
      send_assignment_notification!(pickup_offer, contact_info) if contact_info.present?
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
        # Auto-create draft lottery linked to this donation
        create_lottery_draft! if topic_id.present?
      end
      # Auto-close after pickup
      close_automatically!
      # Send initial PM notification
      send_pickup_notification!
    end

    # Close the donation
    #
    # @return [Boolean] true if successful
    def close!
      update!(state: "closed")
    end

    # Check if the picker has completed required action after pickup
    # Returns true if either:
    # - A lottery was created and published (active/finished state)
    # - An Erhaltungsbericht was created for this donation
    #
    # @return [Boolean] true if action completed
    def pickup_action_completed?
      # Check if lottery was published (not just draft)
      return true if lottery&.active? || lottery&.finished?

      # Check if an Erhaltungsbericht exists for this donation
      # (Look for topics in Erhaltungsberichte category with donation_id custom field)
      erhaltungsberichte_category_id = SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id
      return false if erhaltungsberichte_category_id.blank?

      Topic
        .where(category_id: erhaltungsberichte_category_id)
        .joins(:_custom_fields)
        .where(topic_custom_fields: { name: "donation_id", value: id.to_s })
        .exists?
    end

    private

    # Send PM notification when donation offer is assigned to a picker
    #
    # @param pickup_offer [PickupOffer] The assigned offer
    # @param contact_info [String] Donor's contact information provided by facilitator
    def send_assignment_notification!(pickup_offer, contact_info)
      return unless topic

      picker = pickup_offer.user
      return unless picker

      # Send PM to picker with donor's contact information
      PostCreator.create!(
        Discourse.system_user,
        title:
          I18n.t(
            "vzekc_verlosung.notifications.donation_assigned.title",
            locale: picker.effective_locale,
            topic_title: topic.title,
          ),
        raw:
          I18n.t(
            "vzekc_verlosung.notifications.donation_assigned.body",
            locale: picker.effective_locale,
            username: picker.username,
            topic_title: topic.title,
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
            contact_info: contact_info,
            facilitator_username: facilitator.username,
          ),
        archetype: Archetype.private_message,
        subtype: TopicSubtype.system_message,
        target_usernames: picker.username,
        skip_validations: true,
      )
    end

    # Automatically close donation after pickup
    def close_automatically!
      close! if picked_up?
    end

    # Send initial PM notification when donation is marked as picked up
    # Reminds picker to either write Erhaltungsbericht or create lottery
    def send_pickup_notification!
      return unless topic

      # Get the assigned offer (picker)
      assigned_offer = pickup_offers.find_by(state: %w[assigned picked_up])
      return unless assigned_offer

      picker = assigned_offer.user
      return unless picker

      # Send PM to picker
      PostCreator.create!(
        Discourse.system_user,
        title:
          I18n.t(
            "vzekc_verlosung.reminders.donation_picked_up.title",
            locale: picker.effective_locale,
            topic_title: topic.title,
          ),
        raw:
          I18n.t(
            "vzekc_verlosung.reminders.donation_picked_up.body",
            locale: picker.effective_locale,
            username: picker.username,
            topic_title: topic.title,
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
          ),
        archetype: Archetype.private_message,
        subtype: TopicSubtype.system_message,
        target_usernames: picker.username,
        skip_validations: true,
      )
    end

    # Auto-create draft lottery when donation is picked up
    def create_lottery_draft!
      # Don't create if lottery already exists
      return if lottery.present?

      VzekcVerlosung::Lottery.create!(
        topic_id: topic_id,
        donation_id: id,
        state: "draft",
        duration_days: 14, # Default 14 days
        drawing_mode: "automatic", # Default to automatic drawing
      )
    end
  end
end

# == Schema Information
#
# Table name: vzekc_verlosung_donations
#
#  id               :bigint           not null, primary key
#  last_reminded_at :datetime
#  postcode         :string           not null
#  published_at     :datetime
#  state            :string           default("draft"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  creator_user_id  :bigint           not null
#  topic_id         :bigint
#
# Indexes
#
#  index_vzekc_verlosung_donations_on_creator_user_id         (creator_user_id)
#  index_vzekc_verlosung_donations_on_state                   (state)
#  index_vzekc_verlosung_donations_on_state_and_published_at  (state,published_at)
#  index_vzekc_verlosung_donations_on_topic_id                (topic_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (creator_user_id => users.id) ON DELETE => cascade
#  fk_rails_...  (topic_id => topics.id) ON DELETE => cascade
#
