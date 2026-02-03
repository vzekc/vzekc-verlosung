# frozen_string_literal: true

# == Schema Information
#
# Table name: vzekc_verlosung_merch_packets
#
#  id                     :bigint           not null, primary key
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  donation_id            :bigint           not null
#  donor_city             :string
#  donor_company          :string
#  donor_email            :string
#  donor_name             :string
#  donor_postcode         :string
#  donor_street           :string
#  donor_street_number    :string
#  shipped_at             :datetime
#  shipped_by_user_id     :bigint
#  state                  :string           default("pending"), not null
#  tracking_info          :text
#
# Indexes
#
#  idx_merch_packets_for_archival                          (state,shipped_at)
#  index_vzekc_verlosung_merch_packets_on_donation_id      (donation_id) UNIQUE
#  index_vzekc_verlosung_merch_packets_on_shipped_by_user_id  (shipped_by_user_id)
#  index_vzekc_verlosung_merch_packets_on_state            (state)
#
# Foreign Keys
#
#  fk_rails_...  (donation_id => vzekc_verlosung_donations.id) ON DELETE => cascade
#  fk_rails_...  (shipped_by_user_id => users.id) ON DELETE => nullify
#
module VzekcVerlosung
  # Model for tracking merch packet fulfillment for donors
  #
  # When a donation is picked up, the donor receives a merch packet from the organization.
  # This model tracks the donor's address and shipment status.
  #
  # States:
  # - pending: Waiting to be shipped
  # - shipped: Shipped to donor
  # - archived: Personal data anonymized (4 weeks after shipping)
  #
  # @attr donation_id [Integer] Associated donation
  # @attr donor_name [String] Donor's name (required unless archived)
  # @attr donor_company [String] Optional company/zusatz
  # @attr donor_street [String] Street name (required unless archived)
  # @attr donor_street_number [String] Street number (required unless archived)
  # @attr donor_postcode [String] PLZ (required unless archived)
  # @attr donor_city [String] City (required unless archived)
  # @attr donor_email [String] Optional email for tracking notification
  # @attr state [String] Current state: pending, shipped, archived
  # @attr tracking_info [String] Optional tracking information
  # @attr shipped_at [DateTime] When the packet was shipped
  # @attr shipped_by_user_id [Integer] User who marked as shipped
  #
  class MerchPacket < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_merch_packets"

    STATES = %w[pending shipped archived].freeze

    belongs_to :donation, class_name: "VzekcVerlosung::Donation"
    belongs_to :shipped_by_user, class_name: "User", optional: true

    validates :state, presence: true, inclusion: { in: STATES }
    validate :address_required_unless_archived

    scope :pending, -> { where(state: "pending") }
    scope :shipped, -> { where(state: "shipped") }
    scope :archived, -> { where(state: "archived") }
    scope :needs_archival, -> { shipped.where("shipped_at < ?", 4.weeks.ago) }

    # Check if in pending state
    #
    # @return [Boolean]
    def pending?
      state == "pending"
    end

    # Check if in shipped state
    #
    # @return [Boolean]
    def shipped?
      state == "shipped"
    end

    # Check if in archived state
    #
    # @return [Boolean]
    def archived?
      state == "archived"
    end

    # Mark the packet as shipped
    #
    # @param user [User] User marking the packet as shipped
    # @param tracking_info [String] Optional tracking information
    # @return [Boolean] true if successful
    def mark_shipped!(user, tracking_info: nil)
      update!(
        state: "shipped",
        shipped_at: Time.zone.now,
        shipped_by_user: user,
        tracking_info: tracking_info,
      )

      send_shipped_notification!
    end

    # Archive the packet and anonymize personal data
    #
    # @return [Boolean] true if successful
    def archive!
      update!(
        state: "archived",
        donor_name: nil,
        donor_company: nil,
        donor_street: nil,
        donor_street_number: nil,
        donor_postcode: nil,
        donor_city: nil,
        donor_email: nil,
      )
    end

    # Clear all personal data
    #
    # @return [Boolean] true if successful
    def anonymize!
      update!(
        donor_name: nil,
        donor_company: nil,
        donor_street: nil,
        donor_street_number: nil,
        donor_postcode: nil,
        donor_city: nil,
        donor_email: nil,
      )
    end

    # Get formatted address for display/copying
    #
    # @return [String] Formatted postal address
    def formatted_address
      return "" if archived?

      lines = []
      lines << donor_name if donor_name.present?
      lines << donor_company if donor_company.present?
      lines << "#{donor_street} #{donor_street_number}".strip if donor_street.present?
      lines << "#{donor_postcode} #{donor_city}".strip if donor_postcode.present? || donor_city.present?
      lines.join("\n")
    end

    private

    # Validate that address fields are present unless archived
    def address_required_unless_archived
      return if archived?

      errors.add(:donor_name, :blank) if donor_name.blank?
      errors.add(:donor_street, :blank) if donor_street.blank?
      errors.add(:donor_street_number, :blank) if donor_street_number.blank?
      errors.add(:donor_postcode, :blank) if donor_postcode.blank?
      errors.add(:donor_city, :blank) if donor_city.blank?
    end

    # Send email notification to donor when packet is shipped
    def send_shipped_notification!
      return if donor_email.blank?

      NotificationService.send_merch_packet_shipped_email(
        email: donor_email,
        donor_name: donor_name,
        tracking_info: tracking_info,
        donation: donation,
      )
    end
  end
end
