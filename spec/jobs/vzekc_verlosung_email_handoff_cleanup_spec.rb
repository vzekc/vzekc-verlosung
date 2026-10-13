# frozen_string_literal: true

require "rails_helper"

describe Jobs::VzekcVerlosungEmailHandoffCleanup do
  def create_handoff(expires_at)
    VzekcVerlosung::EmailHandoff.create!(
      token_digest: SecureRandom.hex,
      invocation_id: SecureRandom.uuid,
      expires_at: expires_at,
    )
  end

  it "deletes only expired handoffs" do
    expired = create_handoff(1.minute.ago)
    current = create_handoff(10.minutes.from_now)

    described_class.new.execute({})

    expect(VzekcVerlosung::EmailHandoff.exists?(expired.id)).to eq(false)
    expect(VzekcVerlosung::EmailHandoff.exists?(current.id)).to eq(true)
  end
end
