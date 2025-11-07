# frozen_string_literal: true

module Jobs
  class VzekcVerlosungEndedReminder < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      # Only run at configured hour (server local time)
      return unless Time.zone.now.hour == (SiteSetting.vzekc_verlosung_reminder_hour || 7)

      # Find all active lotteries that have ended but not been drawn
      Topic
        .where(deleted_at: nil)
        .joins(:_custom_fields)
        .where(topic_custom_fields: { name: "lottery_state", value: "active" })
        .each do |topic|
          # Check if lottery has ended
          next unless topic.lottery_ends_at
          next if topic.lottery_ends_at > Time.zone.now

          # Check if not drawn yet
          next if topic.lottery_drawn?

          user = topic.user
          next unless user

          # Send reminder PM
          PostCreator.create!(
            Discourse.system_user,
            title: I18n.t("vzekc_verlosung.reminders.ended.title", locale: user.effective_locale),
            raw:
              I18n.t(
                "vzekc_verlosung.reminders.ended.body",
                locale: user.effective_locale,
                username: user.username,
                topic_title: topic.title,
                ended_at: topic.lottery_ends_at.strftime("%d.%m.%Y"),
                topic_url: "#{Discourse.base_url}#{topic.relative_url}",
              ),
            archetype: Archetype.private_message,
            subtype: TopicSubtype.system_message,
            target_usernames: user.username,
            skip_validations: true,
          )
        end
    end
  end
end
