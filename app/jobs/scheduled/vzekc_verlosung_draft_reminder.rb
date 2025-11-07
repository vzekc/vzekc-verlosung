# frozen_string_literal: true

module Jobs
  class VzekcVerlosungDraftReminder < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      # Only run at configured hour (server local time)
      return unless Time.zone.now.hour == (SiteSetting.vzekc_verlosung_reminder_hour || 7)

      # Find all draft lotteries
      draft_topics =
        Topic
          .where(deleted_at: nil)
          .joins(:_custom_fields)
          .where(topic_custom_fields: { name: "lottery_state", value: "draft" })

      draft_topics.each do |topic|
        user = topic.user
        next unless user

        # Send reminder PM
        PostCreator.create!(
          Discourse.system_user,
          title: I18n.t("vzekc_verlosung.reminders.draft.title", locale: user.effective_locale),
          raw:
            I18n.t(
              "vzekc_verlosung.reminders.draft.body",
              locale: user.effective_locale,
              username: user.username,
              topic_title: topic.title,
              created_at: topic.created_at.strftime("%d.%m.%Y"),
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
