# frozen_string_literal: true

RSpec.describe TopicQuery do
  fab!(:user)
  fab!(:owner, :user)
  fab!(:topic)
  fab!(:draft_topic) { Fabricate(:topic, user: owner) }

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    Fabricate(:donation, topic_id: draft_topic.id, creator_user_id: owner.id)
  end

  let(:latest_topic_ids) { ->(for_user) { TopicQuery.new(for_user).list_latest.topics.map(&:id) } }

  it "hides draft donation topics from other users" do
    expect(latest_topic_ids.(user)).to include(topic.id)
    expect(latest_topic_ids.(user)).not_to include(draft_topic.id)
  end

  it "shows draft donation topics to their owner" do
    expect(latest_topic_ids.(owner)).to include(draft_topic.id)
  end

  it "keeps listing topics while a draft donation has no topic yet" do
    Fabricate(:donation, topic_id: nil)

    expect(latest_topic_ids.(user)).to include(topic.id)
    expect(latest_topic_ids.(user)).not_to include(draft_topic.id)
  end
end
