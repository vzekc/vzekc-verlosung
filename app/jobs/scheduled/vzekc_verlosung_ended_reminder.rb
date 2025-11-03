# frozen_string_literal: true

module Jobs
  class VzekcVerlosungEndedReminder < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled
      return unless SiteSetting.vzekc_verlosung_ended_reminder_enabled

      # Find all active lotteries that have ended but not been drawn
      Topic
        .where(deleted_at: nil)
        .joins(:_custom_fields)
        .where(
          topic_custom_fields: {
            name: "lottery_state",
            value: "active",
          },
        )
        .each do |topic|
          # Check if lottery has ended
          next unless topic.lottery_ends_at
          next unless topic.lottery_ends_at <= Time.zone.now

          # Check if not drawn yet
          next if topic.lottery_drawn?

          user = topic.user
          next unless user

          # Send reminder email
          subject = SiteSetting.vzekc_verlosung_ended_reminder_subject
          body =
            SiteSetting.vzekc_verlosung_ended_reminder_body.gsub("%{username}", user.username).gsub(
              "%{topic_title}",
              topic.title,
            ).gsub("%{ended_at}", topic.lottery_ends_at.strftime("%d.%m.%Y")).gsub(
              "%{topic_url}",
              "#{Discourse.base_url}#{topic.relative_url}",
            )

          message = UserNotifications.send_mail(user, :custom, subject: subject, body: body)
          Email::Sender.new(message, :vzekc_verlosung_ended_reminder).send
        end
    end
  end
end
