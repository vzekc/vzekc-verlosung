# frozen_string_literal: true

require_dependency "email/message_builder"

class VzekcVerlosungMailer < ActionMailer::Base
  include Email::BuildEmailHelper

  def draft_reminder(user, topic)
    body =
      SiteSetting.vzekc_verlosung_draft_reminder_body.gsub("%{username}", user.username).gsub(
        "%{topic_title}",
        topic.title,
      ).gsub("%{created_at}", topic.created_at.strftime("%d.%m.%Y")).gsub(
        "%{topic_url}",
        "#{Discourse.base_url}#{topic.relative_url}",
      )

    build_email(
      user.email,
      template: "vzekc_verlosung_reminder",
      email_subject: SiteSetting.vzekc_verlosung_draft_reminder_subject,
      body: body,
    )
  end

  def ended_reminder(user, topic)
    body =
      SiteSetting.vzekc_verlosung_ended_reminder_body.gsub("%{username}", user.username).gsub(
        "%{topic_title}",
        topic.title,
      ).gsub("%{ended_at}", topic.lottery_ends_at.strftime("%d.%m.%Y")).gsub(
        "%{topic_url}",
        "#{Discourse.base_url}#{topic.relative_url}",
      )

    build_email(
      user.email,
      template: "vzekc_verlosung_reminder",
      email_subject: SiteSetting.vzekc_verlosung_ended_reminder_subject,
      body: body,
    )
  end
end
