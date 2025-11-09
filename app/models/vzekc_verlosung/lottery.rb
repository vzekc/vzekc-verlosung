# frozen_string_literal: true

module VzekcVerlosung
  class Lottery < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_lotteries"

    # Associations
    belongs_to :topic
    has_many :lottery_packets, class_name: "VzekcVerlosung::LotteryPacket", dependent: :destroy
    has_many :lottery_tickets,
             class_name: "VzekcVerlosung::LotteryTicket",
             through: :lottery_packets,
             source: :lottery_tickets

    # Validations
    validates :topic_id, presence: true, uniqueness: true
    validates :state, presence: true, inclusion: { in: %w[draft active finished] }
    validates :duration_days,
              numericality: {
                greater_than_or_equal_to: 7,
                less_than_or_equal_to: 28,
              },
              allow_nil: true
    validates :display_id,
              presence: true,
              uniqueness: true,
              numericality: {
                only_integer: true,
                greater_than: 400,
              }

    # Scopes
    scope :draft, -> { where(state: "draft") }
    scope :active, -> { where(state: "active") }
    scope :finished, -> { where(state: "finished") }
    scope :ending_soon, -> { active.where("ends_at <= ?", 1.day.from_now) }
    scope :ready_to_draw, -> { active.where("ends_at <= ?", Time.zone.now).where(drawn_at: nil) }

    # State helpers
    def draft?
      state == "draft"
    end

    def active?
      state == "active"
    end

    def finished?
      state == "finished"
    end

    def drawn?
      drawn_at.present?
    end

    # Transition methods
    def publish!(ends_at_time)
      update!(state: "active", ends_at: ends_at_time)
    end

    def finish!
      update!(state: "finished")
    end

    def mark_drawn!(results_data)
      update!(drawn_at: Time.zone.now, results: results_data)
    end

    # Query helpers
    def participants
      post_ids = lottery_packets.pluck(:post_id)
      user_ids = VzekcVerlosung::LotteryTicket.where(post_id: post_ids).distinct.pluck(:user_id)
      User.where(id: user_ids)
    end

    def participant_count
      post_ids = lottery_packets.pluck(:post_id)
      VzekcVerlosung::LotteryTicket.where(post_id: post_ids).distinct.count(:user_id)
    end
  end
end
