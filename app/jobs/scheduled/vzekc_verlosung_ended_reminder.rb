# frozen_string_literal: true

module Jobs
  class VzekcVerlosungEndedReminder < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      # Only run at configured hour (server local time)
      return unless Time.zone.now.hour == (SiteSetting.vzekc_verlosung_reminder_hour || 7)

      # Find all active lotteries that have ended but not been drawn
      VzekcVerlosung::Lottery
        .ready_to_draw
        .includes(:topic, lottery_packets: :lottery_tickets)
        .find_each do |lottery|
          topic = lottery.topic
          next unless topic

          user = topic.user
          next unless user

          # If no drawable tickets exist, auto-finish the lottery
          unless lottery.has_drawable_tickets?
            lottery.finish_without_participants!

            Rails.logger.info(
              "[VzekcVerlosung] Auto-finished lottery #{lottery.id} (topic #{topic.id}) - no participants",
            )

            # Notify the creator about no participants
            VzekcVerlosung::NotificationService.notify(
              :no_participants_reminder,
              recipient: user,
              context: {
                lottery: lottery,
              },
            )
            next
          end

          # Send reminder PM for lotteries that need drawing
          VzekcVerlosung::NotificationService.notify(
            :ended_reminder,
            recipient: user,
            context: {
              lottery: lottery,
            },
          )
        end
    end
  end
end
