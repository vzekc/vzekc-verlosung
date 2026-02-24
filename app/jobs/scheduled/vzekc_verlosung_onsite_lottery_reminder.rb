# frozen_string_literal: true

module Jobs
  # Scheduled job to send reminders about upcoming onsite lottery events
  #
  # Runs daily at the configured reminder hour.
  # Sends reminders at 4 weeks (28 days) and 1 week (7 days) before the event.
  # Groups donations by picker and sends one PM per picker listing all their packages.
  class VzekcVerlosungOnsiteLotteryReminder < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      # Only run at configured hour
      return unless Time.zone.now.hour == (SiteSetting.vzekc_verlosung_reminder_hour || 7)

      event = VzekcVerlosung::OnsiteLotteryEvent.current_event
      return unless event

      days_until = (event.event_date - Date.current).to_i
      return if [28, 7].exclude?(days_until)

      # Avoid duplicate sends on same day
      return if event.last_reminded_at.present? && event.last_reminded_at > 24.hours.ago

      # Group donations by picker
      donations_by_picker = {}

      event
        .donations
        .includes(:topic, :pickup_offers)
        .find_each do |donation|
          next unless donation.topic

          assigned_offer = donation.pickup_offers.find_by(state: %w[assigned picked_up])
          next unless assigned_offer

          picker = assigned_offer.user
          next unless picker

          donations_by_picker[picker] ||= []
          donations_by_picker[picker] << donation
        end

      # Send one PM per picker
      donations_by_picker.each do |picker, donations|
        donation_list =
          donations
            .map { |d| "- [#{d.topic.title}](#{Discourse.base_url}#{d.topic.relative_url})" }
            .join("\n")

        VzekcVerlosung::NotificationService.notify(
          :onsite_lottery_reminder,
          recipient: picker,
          context: {
            event: event,
            donation_list: donation_list,
            days_until: days_until,
          },
        )
      end

      # Update last_reminded_at to avoid duplicate sends
      event.update_column(:last_reminded_at, Time.zone.now)
    end
  end
end
