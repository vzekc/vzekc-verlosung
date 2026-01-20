# frozen_string_literal: true

module Jobs
  class VzekcVerlosungEndingTomorrowReminder < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      # Only run at configured hour (server local time)
      return unless Time.zone.now.hour == (SiteSetting.vzekc_verlosung_reminder_hour || 7)

      # Tomorrow's date range: tomorrow 00:00:00 to day-after-tomorrow 00:00:00 (exclusive)
      tomorrow_start = Time.zone.now.tomorrow.beginning_of_day
      day_after_tomorrow = tomorrow_start + 1.day

      # Find active lotteries ending tomorrow
      VzekcVerlosung::Lottery
        .active
        .where(ends_at: tomorrow_start...day_after_tomorrow)
        .includes(:topic)
        .find_each do |lottery|
          topic = lottery.topic
          next unless topic

          user = topic.user
          next unless user

          VzekcVerlosung::NotificationService.notify(
            :ending_tomorrow_reminder,
            recipient: user,
            context: {
              lottery: lottery,
            },
          )
        end
    end
  end
end
