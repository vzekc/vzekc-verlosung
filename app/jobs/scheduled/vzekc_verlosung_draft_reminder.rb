# frozen_string_literal: true

module Jobs
  class VzekcVerlosungDraftReminder < ::Jobs::Scheduled
    daily at: -> { (SiteSetting.vzekc_verlosung_reminder_hour || 7).hours }

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled
      return unless SiteSetting.vzekc_verlosung_draft_reminder_enabled

      # Find all draft lotteries
      draft_topics =
        Topic
          .where(deleted_at: nil)
          .joins(:_custom_fields)
          .where(topic_custom_fields: { name: "lottery_state", value: "draft" })

      draft_topics.each do |topic|
        user = topic.user
        next unless user

        # Send reminder email
        message = VzekcVerlosungMailer.draft_reminder(user, topic)
        Email::Sender.new(message, :vzekc_verlosung_draft_reminder).send
      end
    end
  end
end
