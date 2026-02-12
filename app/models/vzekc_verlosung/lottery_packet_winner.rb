# frozen_string_literal: true

module VzekcVerlosung
  class LotteryPacketWinner < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_lottery_packet_winners"

    # Fulfillment state constants
    FULFILLMENT_STATES = %w[won shipped received completed].freeze

    # Associations
    belongs_to :lottery_packet, class_name: "VzekcVerlosung::LotteryPacket"
    belongs_to :winner, class_name: "User", foreign_key: :winner_user_id
    belongs_to :erhaltungsbericht_topic,
               class_name: "Topic",
               foreign_key: :erhaltungsbericht_topic_id,
               optional: true
    belongs_to :winner_pm_topic,
               class_name: "Topic",
               foreign_key: :winner_pm_topic_id,
               optional: true

    # Validations
    validates :lottery_packet_id, presence: true
    validates :winner_user_id, presence: true
    validates :instance_number,
              presence: true,
              numericality: {
                only_integer: true,
                greater_than: 0,
              }
    validates :instance_number, uniqueness: { scope: :lottery_packet_id }
    validates :winner_user_id,
              uniqueness: {
                scope: :lottery_packet_id,
                message: "can only win one instance per packet",
              }
    validates :fulfillment_state, presence: true, inclusion: { in: FULFILLMENT_STATES }
    validate :instance_number_within_quantity

    # Scopes
    scope :ordered, -> { order(:instance_number) }
    # State-based scopes (use these for business logic decisions)
    scope :shipped, -> { where(fulfillment_state: %w[shipped received completed]) }
    scope :unshipped, -> { where(fulfillment_state: "won") }
    scope :collected, -> { where(fulfillment_state: %w[received completed]) }
    scope :uncollected, -> { where(fulfillment_state: %w[won shipped]) }
    scope :with_report, -> { where.not(erhaltungsbericht_topic_id: nil) }
    scope :without_report, -> { where(erhaltungsbericht_topic_id: nil) }
    scope :requiring_report,
          -> do
            joins(:lottery_packet).where(
              vzekc_verlosung_lottery_packets: {
                erhaltungsbericht_required: true,
              },
            )
          end
    scope :won, -> { where(fulfillment_state: "won") }
    scope :fulfillment_shipped, -> { where(fulfillment_state: "shipped") }
    scope :received, -> { where(fulfillment_state: "received") }
    scope :completed, -> { where(fulfillment_state: "completed") }
    scope :pending_fulfillment, -> { where.not(fulfillment_state: "completed") }

    # Fulfillment state helpers
    def won?
      fulfillment_state == "won"
    end

    def fulfillment_shipped?
      fulfillment_state == "shipped"
    end

    def received?
      fulfillment_state == "received"
    end

    def fulfillment_completed?
      fulfillment_state == "completed"
    end

    # State-based helpers (use these for business logic decisions)
    def shipped?
      %w[shipped received completed].include?(fulfillment_state)
    end

    def collected?
      %w[received completed].include?(fulfillment_state)
    end

    def has_report?
      erhaltungsbericht_topic_id.present?
    end

    # State transition methods
    def mark_shipped!(timestamp = Time.zone.now, tracking_info: nil)
      update!(shipped_at: timestamp, tracking_info: tracking_info, fulfillment_state: "shipped")
    end

    def mark_collected!(timestamp = Time.zone.now)
      new_state = lottery_packet.erhaltungsbericht_required ? "received" : "completed"
      update!(collected_at: timestamp, fulfillment_state: new_state)
    end

    def mark_handed_over!(timestamp = Time.zone.now)
      new_state = lottery_packet.erhaltungsbericht_required ? "received" : "completed"
      update!(shipped_at: timestamp, collected_at: timestamp, fulfillment_state: new_state)
    end

    def link_report!(topic)
      update!(erhaltungsbericht_topic_id: topic.id, fulfillment_state: "completed")
    end

    def mark_complete!
      update!(fulfillment_state: "completed")
    end

    private

    def instance_number_within_quantity
      return unless lottery_packet

      if instance_number > lottery_packet.quantity
        errors.add(:instance_number, "exceeds packet quantity")
      end
    end
  end
end

# == Schema Information
#
# Table name: vzekc_verlosung_lottery_packet_winners
#
#  id                         :bigint           not null, primary key
#  collected_at               :datetime
#  fulfillment_state          :string           default("won"), not null
#  instance_number            :integer          not null
#  shipped_at                 :datetime
#  tracking_info              :text
#  won_at                     :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  erhaltungsbericht_topic_id :bigint
#  lottery_packet_id          :bigint           not null
#  winner_pm_topic_id         :bigint
#  winner_user_id             :bigint           not null
#
# Indexes
#
#  idx_lottery_packet_winners_on_fulfillment_state  (fulfillment_state)
#  idx_lottery_packet_winners_on_packet_id          (lottery_packet_id)
#  idx_lottery_packet_winners_on_user_id            (winner_user_id)
#  idx_lottery_packet_winners_unique_instance       (lottery_packet_id,instance_number) UNIQUE
#  idx_lottery_packet_winners_unique_user           (lottery_packet_id,winner_user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (erhaltungsbericht_topic_id => topics.id) ON DELETE => nullify
#  fk_rails_...  (lottery_packet_id => vzekc_verlosung_lottery_packets.id) ON DELETE => cascade
#  fk_rails_...  (winner_pm_topic_id => topics.id) ON DELETE => nullify
#  fk_rails_...  (winner_user_id => users.id) ON DELETE => cascade
#
