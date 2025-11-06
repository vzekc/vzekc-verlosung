# frozen_string_literal: true

require_dependency "email/message_builder"

class VzekcVerlosungMailer < ActionMailer::Base
  include Email::BuildEmailHelper

  def draft_reminder(user, topic)
    build_email(
      user.email,
      template: "vzekc_verlosung_mailer.draft_reminder",
      locale: user.effective_locale,
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
      locale: user.effective_locale,
      username: user.username,
      topic_title: topic.title,
      ended_at: topic.lottery_ends_at.strftime("%d.%m.%Y"),
      topic_url: "#{Discourse.base_url}#{topic.relative_url}",
    )
  end

  def uncollected_reminder(user, topic, uncollected_count, days_since_drawn, packet_list)
    build_email(
      user.email,
      template: "vzekc_verlosung_mailer.uncollected_reminder",
      locale: user.effective_locale,
      username: user.username,
      topic_title: topic.title,
      uncollected_count: uncollected_count,
      days_since_drawn: days_since_drawn,
      packet_list: packet_list,
      topic_url: "#{Discourse.base_url}#{topic.relative_url}",
    )
  end
end
