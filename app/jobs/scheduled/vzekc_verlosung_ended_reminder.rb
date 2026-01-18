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

          # Skip if lottery creator is no longer an active member
          next unless VzekcVerlosung::MemberChecker.active_member?(user)

          # If no drawable tickets exist, auto-finish the lottery
          unless lottery.has_drawable_tickets?
            lottery.finish_without_participants!

            Rails.logger.info(
              "[VzekcVerlosung] Auto-finished lottery #{lottery.id} (topic #{topic.id}) - no participants",
            )

            # Notify the creator
            PostCreator.create!(
              Discourse.system_user,
              title:
                I18n.t(
                  "vzekc_verlosung.reminders.no_participants.title",
                  locale: user.effective_locale,
                ),
              raw:
                I18n.t(
                  "vzekc_verlosung.reminders.no_participants.body",
                  locale: user.effective_locale,
                  username: user.username,
                  topic_title: topic.title,
                  ended_at: lottery.ends_at.strftime("%d.%m.%Y"),
                  topic_url: "#{Discourse.base_url}#{topic.relative_url}",
                ),
              archetype: Archetype.private_message,
              subtype: TopicSubtype.system_message,
              target_usernames: user.username,
              skip_validations: true,
            )
            next
          end

          # Send reminder PM for lotteries that need drawing
          PostCreator.create!(
            Discourse.system_user,
            title: I18n.t("vzekc_verlosung.reminders.ended.title", locale: user.effective_locale),
            raw:
              I18n.t(
                "vzekc_verlosung.reminders.ended.body",
                locale: user.effective_locale,
                username: user.username,
                topic_title: topic.title,
                ended_at: lottery.ends_at.strftime("%d.%m.%Y"),
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
