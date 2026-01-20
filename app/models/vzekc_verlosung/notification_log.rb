# frozen_string_literal: true

module VzekcVerlosung
  class NotificationLog < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_notification_logs"

    # Associations
    belongs_to :recipient, class_name: "User", foreign_key: :recipient_user_id
    belongs_to :actor, class_name: "User", foreign_key: :actor_user_id, optional: true
    belongs_to :lottery, class_name: "VzekcVerlosung::Lottery", optional: true
    belongs_to :donation, class_name: "VzekcVerlosung::Donation", optional: true
    belongs_to :lottery_packet, class_name: "VzekcVerlosung::LotteryPacket", optional: true
    belongs_to :topic, optional: true
    belongs_to :post, optional: true

    # Validations
    validates :recipient_user_id, presence: true
    validates :notification_type, presence: true
    validates :delivery_method, presence: true, inclusion: { in: %w[in_app pm] }

    # Scopes
    scope :recent, -> { order(created_at: :desc) }
    scope :successful, -> { where(success: true) }
    scope :failed, -> { where(success: false) }
    scope :for_user, ->(user_id) { where(recipient_user_id: user_id) }
    scope :for_lottery, ->(lottery_id) { where(lottery_id: lottery_id) }
    scope :for_donation, ->(donation_id) { where(donation_id: donation_id) }
    scope :of_type, ->(type) { where(notification_type: type) }
    scope :in_app, -> { where(delivery_method: "in_app") }
    scope :pm, -> { where(delivery_method: "pm") }
  end
end

# == Schema Information
#
# Table name: vzekc_verlosung_notification_logs
#
#  id                :bigint           not null, primary key
#  delivery_method   :string           not null
#  error_message     :string
#  notification_type :string           not null
#  payload           :jsonb
#  success           :boolean          default(TRUE), not null
#  created_at        :datetime         not null
#  actor_user_id     :bigint
#  donation_id       :bigint
#  lottery_id        :bigint
#  lottery_packet_id :bigint
#  post_id           :bigint
#  recipient_user_id :bigint           not null
#  topic_id          :bigint
#
# Indexes
#
#  idx_notification_logs_on_lottery_and_type                     (lottery_id,notification_type)
#  idx_notification_logs_on_recipient_and_created                (recipient_user_id,created_at)
#  index_vzekc_verlosung_notification_logs_on_created_at         (created_at)
#  index_vzekc_verlosung_notification_logs_on_donation_id        (donation_id)
#  index_vzekc_verlosung_notification_logs_on_lottery_id         (lottery_id)
#  index_vzekc_verlosung_notification_logs_on_notification_type  (notification_type)
#  index_vzekc_verlosung_notification_logs_on_recipient_user_id  (recipient_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (actor_user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (donation_id => vzekc_verlosung_donations.id) ON DELETE => cascade
#  fk_rails_...  (lottery_id => vzekc_verlosung_lotteries.id) ON DELETE => cascade
#  fk_rails_...  (lottery_packet_id => vzekc_verlosung_lottery_packets.id) ON DELETE => cascade
#  fk_rails_...  (post_id => posts.id) ON DELETE => nullify
#  fk_rails_...  (recipient_user_id => users.id) ON DELETE => cascade
#  fk_rails_...  (topic_id => topics.id) ON DELETE => nullify
#
