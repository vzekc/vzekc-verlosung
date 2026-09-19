# frozen_string_literal: true

require "rails_helper"

describe Jobs::VzekcVerlosungErhaltungsberichtReminder do
  fab!(:admin)
  fab!(:winner, :user)
  fab!(:erhaltungsberichte_category, :category)
  fab!(:lottery_topic) { Fabricate(:topic, user: admin, title: "Verlosung Amiga 2000") }
  fab!(:lottery) do
    VzekcVerlosung::Lottery.create!(
      topic_id: lottery_topic.id,
      state: "finished",
      duration_days: 14,
      drawn_at: 30.days.ago,
    )
  end
  fab!(:packet_post) { Fabricate(:post, topic: lottery_topic, user: admin) }
  fab!(:packet) do
    VzekcVerlosung::LotteryPacket.create!(
      lottery_id: lottery.id,
      post_id: packet_post.id,
      ordinal: 1,
      title: "Amiga 2000",
      erhaltungsbericht_required: true,
      abholerpaket: false,
    )
  end
  fab!(:winner_entry) do
    VzekcVerlosung::LotteryPacketWinner.create!(
      lottery_packet: packet,
      winner_user_id: winner.id,
      instance_number: 1,
      won_at: 14.days.ago,
      collected_at: 7.days.ago,
      fulfillment_state: "received",
    )
  end

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id = erhaltungsberichte_category.id.to_s
  end

  it "sends a PM linking directly to the composer and to the packet post" do
    expect { described_class.new.execute({}) }.to change { Topic.private_messages.count }.by(1)

    raw = Topic.private_messages.order(:id).last.first_post.raw
    expect(raw).to include("#{Discourse.base_url}/erhaltungsbericht-schreiben/#{packet_post.id}")
    expect(raw).to include(
      "#{Discourse.base_url}/t/#{lottery_topic.slug}/#{lottery_topic.id}/#{packet_post.post_number}",
    )
    expect(raw).not_to include("%{")
  end
end
