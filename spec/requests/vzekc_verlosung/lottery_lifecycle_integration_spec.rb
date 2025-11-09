# frozen_string_literal: true

RSpec.describe "Lottery Full Lifecycle Integration" do
  fab!(:owner) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:participant1) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:participant2) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:participant3) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category)
  fab!(:erhaltungsberichte_category) { Fabricate(:category, name: "Erhaltungsberichte") }

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id = erhaltungsberichte_category.id
    SiteSetting.vzekc_verlosung_reminder_hour = 7
  end

  it "completes full lottery lifecycle with all reminders and state transitions" do
    # STEP 1: Create lottery in draft state
    freeze_time(Time.zone.parse("2025-01-15 10:00:00"))

    sign_in(owner)
    post "/vzekc-verlosung/lotteries.json",
         params: {
           title: "Hardware Verlosung Januar 2025",
           category_id: category.id,
           duration_days: 14,
           packets: [{ title: "GPU Paket" }, { title: "CPU Paket" }, { title: "RAM Paket" }],
         }

    expect(response.status).to eq(200), "Expected 200 but got #{response.status}: #{response.body}"
    lottery_topic = Topic.find(response.parsed_body["main_topic"]["id"])
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: lottery_topic.id)

    expect(lottery.state).to eq("draft")
    expect(lottery.duration_days).to eq(14)

    packet_posts =
      Post.where(topic_id: lottery_topic.id).where("post_number > 1").order(:post_number)
    expect(packet_posts.count).to eq(3)

    # STEP 2: Draft reminder fires next day at 7 AM
    freeze_time(Time.zone.parse("2025-01-16 07:00:00"))

    expect do Jobs::VzekcVerlosungDraftReminder.new.execute({}) end.to change {
      Topic.where(archetype: Archetype.private_message).count
    }.by(1)

    draft_pm = Topic.where(archetype: Archetype.private_message).order(created_at: :desc).first
    expect(draft_pm.allowed_users).to include(owner)
    expect(draft_pm.title.downcase).to include("unpublished").or include("draft")

    # STEP 3: Publish lottery
    freeze_time(Time.zone.parse("2025-01-18 09:00:00"))

    sign_in(owner)
    put "/vzekc-verlosung/lotteries/#{lottery_topic.id}/publish.json"
    expect(response.status).to eq(204)

    lottery.reload
    expect(lottery.state).to eq("active")
    expect(lottery.ends_at).to be_within(1.minute).of(14.days.from_now)

    # STEP 4: Participants buy tickets for different packets
    freeze_time(Time.zone.parse("2025-01-19 14:00:00"))

    sign_in(participant1)
    post "/vzekc-verlosung/tickets.json", params: { post_id: packet_posts[0].id }
    expect(response.status).to eq(200)

    sign_in(participant2)
    post "/vzekc-verlosung/tickets.json", params: { post_id: packet_posts[1].id }
    expect(response.status).to eq(200)

    sign_in(participant3)
    post "/vzekc-verlosung/tickets.json", params: { post_id: packet_posts[2].id }
    expect(response.status).to eq(200)

    # Also add second ticket for participant1 to different packet
    post "/vzekc-verlosung/tickets.json", params: { post_id: packet_posts[0].id }
    expect(response.status).to eq(200)

    expect(VzekcVerlosung::LotteryTicket.count).to eq(4)

    # STEP 5: Ending tomorrow reminder (day before lottery ends at 7 AM)
    freeze_time(lottery.ends_at - 1.day)
    freeze_time(Time.zone.parse("#{Date.current} 07:00:00"))

    pm_count_before = Topic.where(archetype: Archetype.private_message).count

    Jobs::VzekcVerlosungEndingTomorrowReminder.new.execute({})

    expect(Topic.where(archetype: Archetype.private_message).count).to eq(pm_count_before + 1)

    ending_pm = Topic.where(archetype: Archetype.private_message).order(created_at: :desc).first
    expect(ending_pm.title.downcase).to include("tomorrow").or include("ending")

    # STEP 6: Lottery ends
    freeze_time(lottery.ends_at + 2.hours)

    # Lottery is now ready to draw
    expect(VzekcVerlosung::Lottery.ready_to_draw).to include(lottery)

    # STEP 7: Ended reminder (next day at 7 AM)
    freeze_time(lottery.ends_at + 1.day)
    freeze_time(Time.zone.parse("#{Date.current} 07:00:00"))

    pm_count_before = Topic.where(archetype: Archetype.private_message).count

    Jobs::VzekcVerlosungEndedReminder.new.execute({})

    expect(Topic.where(archetype: Archetype.private_message).count).to eq(pm_count_before + 1)

    ended_pm = Topic.where(archetype: Archetype.private_message).order(created_at: :desc).first
    expect(ended_pm.title.downcase).to include("ended").or include("draw")

    # STEP 8: Draw winners
    freeze_time(lottery.ends_at + 1.day + 2.hours)

    sign_in(owner)
    get "/vzekc-verlosung/lotteries/#{lottery_topic.id}/drawing-data.json"
    expect(response.status).to eq(200)

    # Mock the JavaScript lottery drawer to return consistent results
    mock_results = {
      "rngSeed" => "test-seed-12345",
      "drawingTimestamp" => Time.zone.now.iso8601,
      "drawings" => [
        {
          "text" => "Paket 1: GPU Paket",
          "winner" => participant1.username,
          "participants" => [{ "name" => participant1.username, "tickets" => 2 }],
        },
        {
          "text" => "Paket 2: CPU Paket",
          "winner" => participant2.username,
          "participants" => [{ "name" => participant2.username, "tickets" => 1 }],
        },
        {
          "text" => "Paket 3: RAM Paket",
          "winner" => participant3.username,
          "participants" => [{ "name" => participant3.username, "tickets" => 1 }],
        },
      ],
    }

    allow(VzekcVerlosung::JavascriptLotteryDrawer).to receive(:draw).and_return(mock_results)

    post "/vzekc-verlosung/lotteries/#{lottery_topic.id}/draw.json",
         params: {
           results: mock_results,
         }

    expect(response.status).to eq(204)

    lottery.reload
    expect(lottery.state).to eq("finished")
    expect(lottery.drawn_at).to be_within(1.minute).of(Time.zone.now)
    expect(lottery.results).to be_present

    # Verify all packets have winners
    packets =
      VzekcVerlosung::LotteryPacket
        .where(lottery_id: lottery.id)
        .order("posts.post_number")
        .joins(:post)
    expect(packets.count).to eq(3)
    expect(packets.all?(&:has_winner?)).to be true
    expect(packets.map { |p| p.winner.username }).to contain_exactly(
      participant1.username,
      participant2.username,
      participant3.username,
    )

    # STEP 9: Check history - all won, none collected, no erhaltungsberichte
    get "/vzekc-verlosung/history.json"
    expect(response.status).to eq(200)

    history = response.parsed_body
    expect(history["packets"].length).to eq(3)

    history["packets"].each do |packet_data|
      expect(packet_data["winner"]).to be_present
      expect(packet_data["collected_at"]).to be_nil
      expect(packet_data["erhaltungsbericht"]).to be_nil
    end

    # STEP 10: Uncollected reminder fires 7 days after drawing
    freeze_time(lottery.drawn_at + 7.days)

    pm_count_before = Topic.where(archetype: Archetype.private_message).count

    Jobs::VzekcVerlosungUncollectedReminder.new.execute({})

    expect(Topic.where(archetype: Archetype.private_message).count).to eq(pm_count_before + 1)

    uncollected_pm =
      Topic.where(archetype: Archetype.private_message).order(created_at: :desc).first
    expect(uncollected_pm.title).to include("3")
    expect(uncollected_pm.title.downcase).to include("received").or include("collected")

    # STEP 11: Mark first packet as collected
    sign_in(owner)
    post "/vzekc-verlosung/packets/#{packet_posts[0].id}/mark-collected.json"
    expect(response.status).to eq(200)

    packet1 = VzekcVerlosung::LotteryPacket.find_by(post_id: packet_posts[0].id)
    expect(packet1.collected?).to be true
    expect(packet1.collected_at).to be_within(1.minute).of(Time.zone.now)

    # Check history shows collection
    get "/vzekc-verlosung/history.json"
    history = response.parsed_body

    collected_packet = history["packets"].find { |p| p["post_id"] == packet_posts[0].id }
    expect(collected_packet["collected_at"]).to be_present
    uncollected_count = history["packets"].count { |p| p["collected_at"].nil? }
    expect(uncollected_count).to eq(2)

    # STEP 12: Uncollected reminder 14 days after drawing (7 days later)
    freeze_time(lottery.drawn_at + 14.days)

    pm_count_before = Topic.where(archetype: Archetype.private_message).count

    Jobs::VzekcVerlosungUncollectedReminder.new.execute({})

    expect(Topic.where(archetype: Archetype.private_message).count).to eq(pm_count_before + 1)

    uncollected_pm2 =
      Topic.where(archetype: Archetype.private_message).order(created_at: :desc).first
    expect(uncollected_pm2.title).to include("2")

    # STEP 13: Erhaltungsbericht reminder 7 days after collection
    freeze_time(packet1.collected_at + 7.days)

    Jobs::VzekcVerlosungErhaltungsberichtReminder.new.execute({})

    # Find the Erhaltungsbericht PM for participant1
    erhaltungsbericht_pm =
      Topic
        .where(archetype: Archetype.private_message)
        .joins(:topic_allowed_users)
        .where(topic_allowed_users: { user_id: participant1.id })
        .order(created_at: :desc)
        .first

    expect(erhaltungsbericht_pm).to be_present
    expect(erhaltungsbericht_pm.title.downcase).to include("report").or include("reception")

    # STEP 14: Create erhaltungsbericht for first packet
    sign_in(participant1)
    post "/vzekc-verlosung/packets/#{packet_posts[0].id}/create-erhaltungsbericht.json"
    expect(response.status).to eq(200)

    erhaltungsbericht_data = response.parsed_body
    expect(erhaltungsbericht_data["topic_url"]).to be_present

    packet1.reload
    expect(packet1.erhaltungsbericht_topic_id).to be_present

    erhaltungsbericht_topic = Topic.find(packet1.erhaltungsbericht_topic_id)
    expect(erhaltungsbericht_topic.category_id).to eq(erhaltungsberichte_category.id)
    expect(erhaltungsbericht_topic.user_id).to eq(participant1.id)

    # Check history shows erhaltungsbericht
    get "/vzekc-verlosung/history.json"
    history = response.parsed_body

    packet_with_bericht = history["packets"].find { |p| p["post_id"] == packet_posts[0].id }
    expect(packet_with_bericht["erhaltungsbericht"]).to be_present
    expect(packet_with_bericht["erhaltungsbericht"]["topic_id"]).to eq(erhaltungsbericht_topic.id)

    # STEP 15: Collect remaining packets
    freeze_time(lottery.drawn_at + 15.days)

    sign_in(owner)
    post "/vzekc-verlosung/packets/#{packet_posts[1].id}/mark-collected.json"
    expect(response.status).to eq(200)

    post "/vzekc-verlosung/packets/#{packet_posts[2].id}/mark-collected.json"
    expect(response.status).to eq(200)

    # Verify all collected in history
    get "/vzekc-verlosung/history.json"
    history = response.parsed_body

    expect(history["packets"].all? { |p| p["collected_at"].present? }).to be true

    # STEP 16: Create erhaltungsberichte for remaining packets
    freeze_time(lottery.drawn_at + 16.days)

    sign_in(participant2)
    post "/vzekc-verlosung/packets/#{packet_posts[1].id}/create-erhaltungsbericht.json"
    expect(response.status).to eq(200)

    sign_in(participant3)
    post "/vzekc-verlosung/packets/#{packet_posts[2].id}/create-erhaltungsbericht.json"
    expect(response.status).to eq(200)

    # Verify all have erhaltungsberichte
    get "/vzekc-verlosung/history.json"
    history = response.parsed_body

    expect(history["packets"].all? { |p| p["erhaltungsbericht"].present? }).to be true

    # STEP 17: Delete an erhaltungsbericht - verify packet state reverts
    packet2 = VzekcVerlosung::LotteryPacket.find_by(post_id: packet_posts[1].id)
    erhaltungsbericht_id = packet2.erhaltungsbericht_topic_id

    erhaltungsbericht_to_delete = Topic.find(erhaltungsbericht_id)
    erhaltungsbericht_to_delete.destroy!

    # Check history no longer shows erhaltungsbericht
    get "/vzekc-verlosung/history.json"
    history = response.parsed_body

    deleted_packet = history["packets"].find { |p| p["post_id"] == packet_posts[1].id }
    expect(deleted_packet["erhaltungsbericht"]).to be_nil

    # Packet record's ID is automatically nullified due to ON DELETE NULLIFY
    packet2.reload
    expect(packet2.erhaltungsbericht_topic_id).to be_nil
    expect(Topic.find_by(id: erhaltungsbericht_id)).to be_nil

    # STEP 18: Recreate erhaltungsbericht - should work and set new ID
    sign_in(participant2)
    post "/vzekc-verlosung/packets/#{packet_posts[1].id}/create-erhaltungsbericht.json"
    expect(response.status).to eq(200)

    packet2.reload
    expect(packet2.erhaltungsbericht_topic_id).to be_present
    expect(packet2.erhaltungsbericht_topic_id).not_to eq(erhaltungsbericht_id)

    new_erhaltungsbericht = Topic.find(packet2.erhaltungsbericht_topic_id)
    expect(new_erhaltungsbericht).to be_present

    # Final history check
    get "/vzekc-verlosung/history.json"
    history = response.parsed_body

    expect(history["packets"].length).to eq(3)
    expect(history["packets"].all? { |p| p["winner"].present? }).to be true
    expect(history["packets"].all? { |p| p["collected_at"].present? }).to be true
    expect(history["packets"].all? { |p| p["erhaltungsbericht"].present? }).to be true
  end
end
