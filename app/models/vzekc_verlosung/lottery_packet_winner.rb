# frozen_string_literal: true

module VzekcVerlosung
  class LotteryPacketWinner < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_lottery_packet_winners"

    # Associations
    belongs_to :lottery_packet, class_name: "VzekcVerlosung::LotteryPacket"
    belongs_to :winner, class_name: "User", foreign_key: :winner_user_id
    belongs_to :erhaltungsbericht_topic,
               class_name: "Topic",
               foreign_key: :erhaltungsbericht_topic_id,
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
    validate :instance_number_within_quantity

    # Scopes
    scope :ordered, -> { order(:instance_number) }
    scope :shipped, -> { where.not(shipped_at: nil) }
    scope :unshipped, -> { where(shipped_at: nil) }
    scope :collected, -> { where.not(collected_at: nil) }
    scope :uncollected, -> { where(collected_at: nil) }
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

    # Helper methods
    def shipped?
      shipped_at.present?
    end

    def collected?
      collected_at.present?
    end

    def has_report?
      erhaltungsbericht_topic_id.present?
    end

    def mark_shipped!(timestamp = Time.zone.now, tracking_info: nil)
      update!(shipped_at: timestamp, tracking_info: tracking_info)
    end

    def mark_collected!(timestamp = Time.zone.now)
      update!(collected_at: timestamp)
    end

    def mark_handed_over!(timestamp = Time.zone.now)
      update!(shipped_at: timestamp, collected_at: timestamp)
    end

    def link_report!(topic)
      update!(erhaltungsbericht_topic_id: topic.id)
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
#  instance_number            :integer          not null
#  shipped_at                 :datetime
#  tracking_info              :text
#  won_at                     :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  erhaltungsbericht_topic_id :bigint
#  lottery_packet_id          :bigint           not null
#  winner_user_id             :bigint           not null
#
# Indexes
#
#  idx_lottery_packet_winners_on_packet_id     (lottery_packet_id)
#  idx_lottery_packet_winners_on_user_id       (winner_user_id)
#  idx_lottery_packet_winners_unique_instance  (lottery_packet_id,instance_number) UNIQUE
#  idx_lottery_packet_winners_unique_user      (lottery_packet_id,winner_user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (erhaltungsbericht_topic_id => topics.id) ON DELETE => nullify
#  fk_rails_...  (lottery_packet_id => vzekc_verlosung_lottery_packets.id) ON DELETE => cascade
#  fk_rails_...  (winner_user_id => users.id) ON DELETE => cascade
#
