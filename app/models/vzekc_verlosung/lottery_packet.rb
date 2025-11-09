# frozen_string_literal: true

module VzekcVerlosung
  class LotteryPacket < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_lottery_packets"

    # Associations
    belongs_to :lottery, class_name: "VzekcVerlosung::Lottery"
    belongs_to :post
    belongs_to :winner, class_name: "User", foreign_key: :winner_user_id, optional: true
    belongs_to :erhaltungsbericht_topic,
               class_name: "Topic",
               foreign_key: :erhaltungsbericht_topic_id,
               optional: true
    has_many :lottery_tickets,
             class_name: "VzekcVerlosung::LotteryTicket",
             foreign_key: :post_id,
             primary_key: :post_id

    # Validations
    validates :lottery_id, presence: true
    validates :post_id, presence: true, uniqueness: true
    validates :title, presence: true
    validates :ordinal, presence: true, numericality: { only_integer: true, greater_than: 0 }

    # Scopes
    scope :ordered, -> { order(:ordinal) }
    scope :with_winner, -> { where.not(winner_user_id: nil) }
    scope :without_winner, -> { where(winner_user_id: nil) }
    scope :collected, -> { where.not(collected_at: nil) }
    scope :uncollected, -> { with_winner.where(collected_at: nil) }
    scope :with_report, -> { where.not(erhaltungsbericht_topic_id: nil) }
    scope :without_report, -> { where(erhaltungsbericht_topic_id: nil) }
    scope :requiring_report, -> { where(erhaltungsbericht_required: true) }

    # Helper methods
    def has_winner?
      winner_user_id.present?
    end

    def collected?
      collected_at.present?
    end

    def has_report?
      erhaltungsbericht_topic_id.present?
    end

    def mark_winner!(user, timestamp = Time.zone.now)
      update!(winner_user_id: user.id, won_at: timestamp)
    end

    def mark_collected!(timestamp = Time.zone.now)
      update!(collected_at: timestamp)
    end

    def link_report!(topic)
      update!(erhaltungsbericht_topic_id: topic.id)
    end

    # Query helpers
    def participants
      User.where(id: lottery_tickets.select(:user_id)).distinct
    end

    def participant_count
      lottery_tickets.count
    end
  end
end
