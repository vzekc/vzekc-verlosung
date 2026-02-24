# frozen_string_literal: true

module VzekcVerlosung
  class OnsiteLotteryEvent < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_onsite_lottery_events"

    belongs_to :created_by, class_name: "User", foreign_key: :created_by_user_id
    has_many :donations,
             class_name: "VzekcVerlosung::Donation",
             foreign_key: :onsite_lottery_event_id,
             dependent: :nullify

    validates :name, presence: true
    validates :event_date, presence: true
    validate :event_date_in_future, on: :create

    scope :future, -> { where("event_date >= ?", Date.current) }
    scope :past, -> { where("event_date < ?", Date.current) }

    def self.current_event
      future.order(:event_date).first
    end

    def past?
      event_date < Date.current
    end

    def future?
      event_date >= Date.current
    end

    private

    def event_date_in_future
      return if event_date.blank?
      return if event_date >= Date.current

      errors.add(:event_date, "must be in the future")
    end
  end
end

# == Schema Information
#
# Table name: vzekc_verlosung_onsite_lottery_events
#
#  id                 :bigint           not null, primary key
#  event_date         :date             not null
#  last_reminded_at   :datetime
#  name               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  created_by_user_id :bigint           not null
#
# Indexes
#
#  index_vzekc_verlosung_onsite_lottery_events_on_event_date  (event_date)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_user_id => users.id) ON DELETE => cascade
#
