# frozen_string_literal: true

require "rails_helper"

describe Jobs::VzekcVerlosungDonorContactPurge do
  before { SiteSetting.vzekc_verlosung_enabled = true }

  def donation_with_contact(**attrs)
    Fabricate(
      :donation,
      donor_name: "Max Mustermann",
      donor_company: "Muster GmbH",
      donor_email: "max@example.com",
      **attrs,
    )
  end

  it "purges the donor contact of donations closed more than 4 weeks ago" do
    old = donation_with_contact(state: "closed", closed_at: 5.weeks.ago)

    described_class.new.execute({})

    old.reload
    expect([old.donor_name, old.donor_company, old.donor_email]).to all(be_nil)
  end

  it "keeps the donor contact of recently closed and of open donations" do
    recent = donation_with_contact(state: "closed", closed_at: 2.weeks.ago)
    open_donation = donation_with_contact(state: "open")

    described_class.new.execute({})

    expect(recent.reload.donor_email).to eq("max@example.com")
    expect(open_donation.reload.donor_email).to eq("max@example.com")
  end

  context "when plugin is disabled" do
    before { SiteSetting.vzekc_verlosung_enabled = false }

    it "does nothing" do
      old = donation_with_contact(state: "closed", closed_at: 5.weeks.ago)

      described_class.new.execute({})

      expect(old.reload.donor_email).to eq("max@example.com")
    end
  end
end
