# frozen_string_literal: true

module Jobs
  class VzekcVerlosungDraftReminder < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      # Only run at configured hour (server local time)
      return unless Time.zone.now.hour == (SiteSetting.vzekc_verlosung_reminder_hour || 7)

      # Find all draft lotteries
      VzekcVerlosung::Lottery
        .draft
        .includes(:topic)
        .find_each do |lottery|
          topic = lottery.topic
          next unless topic

          user = topic.user
          next unless user

          VzekcVerlosung::NotificationService.notify(
            :draft_reminder,
            recipient: user,
            context: {
              lottery: lottery,
            },
          )
        end
    end
  end
end
