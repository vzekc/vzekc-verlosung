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
    validates :ordinal,
              presence: true,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 0,
              }

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

# == Schema Information
#
# Table name: vzekc_verlosung_lottery_packets
#
#  id                         :bigint           not null, primary key
#  abholerpaket               :boolean          default(FALSE), not null
#  collected_at               :datetime
#  erhaltungsbericht_required :boolean          default(TRUE), not null
#  ordinal                    :integer          not null
#  title                      :string           not null
#  won_at                     :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  erhaltungsbericht_topic_id :bigint
#  lottery_id                 :bigint           not null
#  post_id                    :bigint           not null
#  winner_user_id             :bigint
#
# Indexes
#
#  index_packets_on_collected_and_winner                    (collected_at,winner_user_id) WHERE ((winner_user_id IS NOT NULL) AND (collected_at IS NULL))
#  index_vzekc_verlosung_lottery_packets_on_lottery_id      (lottery_id)
#  index_vzekc_verlosung_lottery_packets_on_post_id         (post_id) UNIQUE
#  index_vzekc_verlosung_lottery_packets_on_winner_user_id  (winner_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (erhaltungsbericht_topic_id => topics.id) ON DELETE => nullify
#  fk_rails_...  (lottery_id => vzekc_verlosung_lotteries.id) ON DELETE => cascade
#  fk_rails_...  (post_id => posts.id) ON DELETE => cascade
#  fk_rails_...  (winner_user_id => users.id) ON DELETE => nullify
#
