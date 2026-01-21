# frozen_string_literal: true

module VzekcVerlosung
  class LotteryPacket < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_lottery_packets"

    # Ignore old columns that are being deprecated (now stored in lottery_packet_winners)
    self.ignored_columns += %w[winner_user_id won_at collected_at erhaltungsbericht_topic_id]

    # State constants
    STATES = %w[pending no_tickets drawn].freeze

    # Associations
    belongs_to :lottery, class_name: "VzekcVerlosung::Lottery"
    belongs_to :post, optional: true
    has_many :lottery_packet_winners,
             class_name: "VzekcVerlosung::LotteryPacketWinner",
             dependent: :destroy
    has_many :lottery_tickets,
             class_name: "VzekcVerlosung::LotteryTicket",
             foreign_key: :post_id,
             primary_key: :post_id,
             dependent: :destroy

    # Validations
    validates :lottery_id, presence: true
    validates :post_id, presence: true, uniqueness: true
    validates :title, presence: true
    validates :ordinal,
              presence: true,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 0,
              }
    validates :quantity,
              presence: true,
              numericality: {
                only_integer: true,
                greater_than: 0,
                less_than_or_equal_to: 100,
              }
    validates :state, presence: true, inclusion: { in: STATES }

    # Scopes
    scope :ordered, -> { order(:ordinal) }
    scope :with_winner, -> { joins(:lottery_packet_winners).distinct }
    scope :without_winner, -> { left_joins(:lottery_packet_winners).where(lottery_packet_winners: { id: nil }) }
    scope :requiring_report, -> { where(erhaltungsbericht_required: true) }
    scope :pending, -> { where(state: "pending") }
    scope :no_tickets, -> { where(state: "no_tickets") }
    scope :drawn, -> { where(state: "drawn") }

    # State helpers
    def pending?
      state == "pending"
    end

    def no_tickets?
      state == "no_tickets"
    end

    def drawn?
      state == "drawn"
    end

    # State transitions
    def mark_no_tickets!
      update!(state: "no_tickets")
    end

    def mark_drawn!
      update!(state: "drawn")
    end

    # Winner-related helper methods
    def has_winner?
      lottery_packet_winners.exists?
    end

    def all_instances_won?
      lottery_packet_winners.count >= quantity
    end

    def remaining_instances
      quantity - lottery_packet_winners.count
    end

    def winners
      lottery_packet_winners.ordered.includes(:winner).map(&:winner)
    end

    def winner_entries
      lottery_packet_winners.ordered.includes(:winner)
    end

    def mark_winner!(user, timestamp = Time.zone.now, instance_number: nil)
      next_instance = instance_number || (lottery_packet_winners.maximum(:instance_number) || 0) + 1
      lottery_packet_winners.create!(
        winner_user_id: user.id,
        won_at: timestamp,
        instance_number: next_instance,
      )
    end

    def mark_winners!(users, timestamp = Time.zone.now)
      users.each_with_index do |user, index|
        mark_winner!(user, timestamp, instance_number: index + 1)
      end
    end

    # Query helpers
    def participants
      User.where(id: lottery_tickets.select(:user_id)).distinct
    end

    def participant_count
      lottery_tickets.count
    end

    def unique_participant_count
      lottery_tickets.distinct.count(:user_id)
    end
  end
end

# == Schema Information
#
# Table name: vzekc_verlosung_lottery_packets
#
#  id                         :bigint           not null, primary key
#  abholerpaket               :boolean          default(FALSE), not null
#  erhaltungsbericht_required :boolean          default(TRUE), not null
#  notifications_silenced     :boolean          default(FALSE), not null
#  ordinal                    :integer          not null
#  quantity                   :integer          default(1), not null
#  state                      :string           default("pending"), not null
#  title                      :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  lottery_id                 :bigint           not null
#  post_id                    :bigint           not null
#
# Indexes
#
#  index_packets_on_collected_and_winner                    (collected_at,winner_user_id) WHERE ((winner_user_id IS NOT NULL) AND (collected_at IS NULL))
#  index_vzekc_verlosung_lottery_packets_on_lottery_id      (lottery_id)
#  index_vzekc_verlosung_lottery_packets_on_post_id         (post_id) UNIQUE
#  idx_lottery_packets_on_state                             (state)
#  index_vzekc_verlosung_lottery_packets_on_winner_user_id  (winner_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (erhaltungsbericht_topic_id => topics.id) ON DELETE => nullify
#  fk_rails_...  (lottery_id => vzekc_verlosung_lotteries.id) ON DELETE => cascade
#  fk_rails_...  (post_id => posts.id) ON DELETE => cascade
#  fk_rails_...  (winner_user_id => users.id) ON DELETE => nullify
#
