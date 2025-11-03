# frozen_string_literal: true

module Jobs
  class VzekcVerlosungEndingTomorrowReminder < ::Jobs::Scheduled
    daily at: -> { (SiteSetting.vzekc_verlosung_reminder_hour || 7).hours }

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled
      return unless SiteSetting.vzekc_verlosung_ending_tomorrow_reminder_enabled

      # Tomorrow's date range: tomorrow 00:00:00 to day-after-tomorrow 00:00:00 (exclusive)
      tomorrow_start = Time.zone.now.tomorrow.beginning_of_day
      day_after_tomorrow = tomorrow_start + 1.day

      # Find active lotteries ending tomorrow
      Topic
        .where(deleted_at: nil)
        .joins(:_custom_fields)
        .where(topic_custom_fields: { name: "lottery_state", value: "active" })
        .each do |topic|
          # Check if lottery ends tomorrow
          next unless topic.lottery_ends_at
          if topic.lottery_ends_at < tomorrow_start || topic.lottery_ends_at >= day_after_tomorrow
            next
          end

          user = topic.user
          next unless user

          # Send notification to lottery creator
          Notification.create!(
            notification_type: Notification.types[:vzekc_verlosung_ending_tomorrow],
            user_id: user.id,
            topic_id: topic.id,
            post_number: 1,
            data: {
              topic_title: topic.title,
              message: "vzekc_verlosung.notifications.lottery_ending_tomorrow",
            }.to_json,
          )
        end
    end
  end
end
