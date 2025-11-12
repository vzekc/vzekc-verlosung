# frozen_string_literal: true

module Jobs
  # Scheduled job to send weekly reminders to users who picked up donations
  # to either create a lottery or write an Erhaltungsbericht
  #
  # Runs every hour but only sends reminders at the configured hour
  # Reminds every 7 days starting from when the donation was marked as picked up
  class VzekcVerlosungDonationPickedUpReminder < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      # Only run at configured hour (server local time)
      return unless Time.zone.now.hour == (SiteSetting.vzekc_verlosung_reminder_hour || 7)

      # Find all picked-up donations that need action reminders
      VzekcVerlosung::Donation
        .needs_pickup_action_reminder
        .includes(:topic)
        .find_each do |donation|
          topic = donation.topic
          next unless topic

          # Get the assigned pickup offer to find the user
          assigned_offer = donation.pickup_offers.find_by(state: %w[assigned picked_up])
          next unless assigned_offer

          user = assigned_offer.user
          next unless user

          # Check if user has already completed required action
          next if donation.pickup_action_completed?

          # Update last_reminded_at timestamp
          donation.update_column(:last_reminded_at, Time.zone.now)

          # Send reminder PM
          PostCreator.create!(
            Discourse.system_user,
            title:
              I18n.t(
                "vzekc_verlosung.reminders.donation_picked_up.title",
                locale: user.effective_locale,
                topic_title: topic.title,
              ),
            raw:
              I18n.t(
                "vzekc_verlosung.reminders.donation_picked_up.body",
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
