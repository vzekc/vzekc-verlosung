# frozen_string_literal: true

Fabricator(:notification_log, class_name: "VzekcVerlosung::NotificationLog") do
  recipient { Fabricate(:user) }
  notification_type "lottery_won"
  delivery_method "in_app"
  success true
end
