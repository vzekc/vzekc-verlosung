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

          # Skip if lottery creator is no longer an active member
          next unless VzekcVerlosung::MemberChecker.active_member?(user)

          # Send reminder PM to lottery creator
          PostCreator.create!(
            Discourse.system_user,
            title:
              I18n.t(
                "vzekc_verlosung.reminders.ending_tomorrow.title",
                locale: user.effective_locale,
              ),
            raw:
              I18n.t(
                "vzekc_verlosung.reminders.ending_tomorrow.body",
                locale: user.effective_locale,
                username: user.username,
                topic_title: topic.title,
                ending_at: lottery.ends_at.strftime("%d.%m.%Y"),
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
