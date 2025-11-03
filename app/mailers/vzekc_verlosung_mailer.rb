# frozen_string_literal: true

require_dependency "email/message_builder"

class VzekcVerlosungMailer < ActionMailer::Base
  include Email::BuildEmailHelper

  def draft_reminder(user, topic)
    build_email(
      user.email,
      template: "vzekc_verlosung_mailer.draft_reminder",
      username: user.username,
      topic_title: topic.title,
      created_at: topic.created_at.strftime("%d.%m.%Y"),
      topic_url: "#{Discourse.base_url}#{topic.relative_url}",
    )
  end

  def ended_reminder(user, topic)
    build_email(
      user.email,
      template: "vzekc_verlosung_mailer.ended_reminder",
      username: user.username,
      topic_title: topic.title,
      ended_at: topic.lottery_ends_at.strftime("%d.%m.%Y"),
      topic_url: "#{Discourse.base_url}#{topic.relative_url}",
    )
  end
end
