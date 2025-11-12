# frozen_string_literal: true

module Jobs
  # Scheduled job to send daily reminders to creators of open donation offers
  #
  # Runs every hour but only sends reminders at the configured hour
  # Reminds creators every 24 hours starting from when the donation was published
  class VzekcVerlosungDonationReminder < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      # Only run at configured hour (server local time)
      return unless Time.zone.now.hour == (SiteSetting.vzekc_verlosung_reminder_hour || 7)

      # Find all open donations that need reminders
      VzekcVerlosung::Donation
        .needs_reminder
        .includes(:topic, :creator)
        .find_each do |donation|
          topic = donation.topic
          next unless topic

          user = donation.creator
          next unless user

          # Update last_reminded_at timestamp
          donation.update_column(:last_reminded_at, Time.zone.now)

          # Send reminder PM
          PostCreator.create!(
            Discourse.system_user,
            title:
              I18n.t("vzekc_verlosung.reminders.donation.title", locale: user.effective_locale),
            raw:
              I18n.t(
                "vzekc_verlosung.reminders.donation.body",
                locale: user.effective_locale,
                username: user.username,
                topic_title: topic.title,
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
