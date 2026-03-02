# frozen_string_literal: true

module Jobs
  class VzekcVerlosungNotifyLotteryEnded < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      lottery_id = args[:lottery_id]
      return unless lottery_id

      lottery = VzekcVerlosung::Lottery.find_by(id: lottery_id)
      return unless lottery

      # Only notify if the lottery is ready to draw (active + ended + not drawn)
      return unless lottery.active? && lottery.ends_at && lottery.ends_at <= Time.zone.now
      return if lottery.drawn?

      topic = lottery.topic
      return unless topic

      owner = topic.user
      return unless owner

      # Dedup: skip if we already sent this notification for this lottery
      already_sent =
        VzekcVerlosung::NotificationLog.exists?(
          notification_type: "lottery_ended",
          lottery_id: lottery.id,
          success: true,
        )
      return if already_sent

      VzekcVerlosung::NotificationService.notify(
        :lottery_ended,
        recipient: owner,
        context: {
          lottery: lottery,
        },
      )
    end
  end
end
