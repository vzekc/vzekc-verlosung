# frozen_string_literal: true

require "rails_helper"

describe Jobs::VzekcVerlosungOnsiteLotteryReminder do
  fab!(:admin)
  fab!(:picker) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:donation_topic) { Fabricate(:topic, title: "PowerBook G4 in 34246 Vellmar") }
  fab!(:event) do
    VzekcVerlosung::OnsiteLotteryEvent.create!(
      name: "Classic Computing 2026 Celle",
      event_date: 28.days.from_now.to_date,
      created_by: admin,
    )
  end
  fab!(:donation) do
    Fabricate(:donation, topic: donation_topic, state: "assigned", onsite_lottery_event: event)
  end
  fab!(:pickup_offer) { Fabricate(:pickup_offer, donation:, user: picker, state: "assigned") }

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_reminder_hour = Time.zone.now.hour
  end

  it "sends the picker a PM with a fully interpolated title" do
    expect { described_class.new.execute({}) }.to change { Topic.private_messages.count }.by(1)

    pm = Topic.private_messages.order(:id).last
    expect(pm.title).to eq(
      I18n.t(
        "vzekc_verlosung.reminders.onsite_lottery.title",
        locale: picker.effective_locale,
        event_name: event.name,
        days_until: 28,
      ),
    )
    expect(pm.title).not_to include("Translation missing")
    expect(pm.first_post.raw).to include(donation_topic.title)
  end
end
