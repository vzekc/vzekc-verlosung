# frozen_string_literal: true

module VzekcVerlosung
  class Lottery < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_lotteries"

    # Associations
    belongs_to :topic
    belongs_to :donation, class_name: "VzekcVerlosung::Donation", optional: true
    has_many :lottery_packets, class_name: "VzekcVerlosung::LotteryPacket", dependent: :destroy
    has_many :lottery_tickets,
             class_name: "VzekcVerlosung::LotteryTicket",
             through: :lottery_packets,
             source: :lottery_tickets

    # Validations
    validates :topic_id, presence: true, uniqueness: true
    validates :state, presence: true, inclusion: { in: %w[active finished] }
    validates :drawing_mode, presence: true, inclusion: { in: %w[automatic manual] }
    validates :duration_days,
              numericality: {
                greater_than_or_equal_to: 7,
                less_than_or_equal_to: 28,
              },
              allow_nil: true

    # Scopes
    scope :active, -> { where(state: "active") }
    scope :finished, -> { where(state: "finished") }
    scope :ending_soon, -> { active.where("ends_at <= ?", 1.day.from_now) }
    scope :ready_to_draw, -> { active.where("ends_at <= ?", Time.zone.now).where(drawn_at: nil) }

    # State helpers
    def active?
      state == "active"
    end

    def finished?
      state == "finished"
    end

    def drawn?
      drawn_at.present?
    end

    # Drawing mode helpers
    def automatic_drawing?
      drawing_mode == "automatic"
    end

    def manual_drawing?
      drawing_mode == "manual"
    end

    # Transition methods
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

    # Check if any drawable packets (non-abholerpaket) have tickets
    #
    # @return [Boolean] true if at least one drawable packet has tickets
    def has_drawable_tickets?
      lottery_packets.where(abholerpaket: false).joins(:lottery_tickets).exists?
    end

    # Check if all required Erhaltungsberichte have been written
    # Uses explicit fulfillment_state instead of checking erhaltungsbericht_topic_id
    #
    # @return [Boolean]
    def all_required_reports_written?
      winners_requiring_reports =
        LotteryPacketWinner.joins(:lottery_packet).where(
          lottery_packet: {
            lottery_id: id,
            erhaltungsbericht_required: true,
          },
        )

      return true if winners_requiring_reports.empty?

      winners_requiring_reports.pending_fulfillment.empty?
    end

    # Returns the completion status for display in the UI
    # Used by topic_list_item serializer for the lottery-status-chip component
    #
    # @return [String] One of: 'active', 'ready_to_draw', 'no_tickets', 'drawn', 'finished'
    def completion_status
      return "active" if active? && !ended?
      return "ready_to_draw" if active? && ended? && !drawn?

      # Lottery has been drawn
      return "active" unless drawn?

      # Check if all packets had no tickets (no_participants scenario)
      drawable_packets = lottery_packets.where(abholerpaket: false)
      if drawable_packets.where(state: "no_tickets").count == drawable_packets.count
        return "no_tickets"
      end

      # Check if all fulfillments are complete
      all_required_reports_written? ? "finished" : "drawn"
    end

    # Check if lottery has ended (past end time)
    def ended?
      ends_at.present? && ends_at <= Time.zone.now
    end

    # Finish lottery without drawing (no participants)
    # Sets drawn_at and results to indicate no drawing was needed
    def finish_without_participants!
      update!(
        state: "finished",
        drawn_at: Time.zone.now,
        results: {
          no_participants: true,
          finished_at: Time.zone.now.iso8601,
        },
      )
    end
  end
end

# == Schema Information
#
# Table name: vzekc_verlosung_lotteries
#
#  id            :bigint           not null, primary key
#  drawing_mode  :string           default("automatic"), not null
#  drawn_at      :datetime
#  duration_days :integer
#  ends_at       :datetime
#  packet_mode   :string           default("mehrere"), not null
#  results       :jsonb
#  state         :string           default("draft"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  donation_id   :bigint
#  topic_id      :bigint           not null
#
# Indexes
#
#  index_lotteries_on_state_and_ends_at            (state,ends_at)
#  index_vzekc_verlosung_lotteries_on_donation_id  (donation_id) UNIQUE
#  index_vzekc_verlosung_lotteries_on_packet_mode  (packet_mode)
#  index_vzekc_verlosung_lotteries_on_state        (state)
#  index_vzekc_verlosung_lotteries_on_topic_id     (topic_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (donation_id => vzekc_verlosung_donations.id) ON DELETE => nullify
#  fk_rails_...  (topic_id => topics.id) ON DELETE => cascade
#
