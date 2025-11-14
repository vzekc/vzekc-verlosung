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
    # CRITICAL: Set as string to match production behavior (SiteSettings are always strings)
    SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id = erhaltungsberichte_category.id.to_s
    SiteSetting.vzekc_verlosung_reminder_hour = 7
  end

  it "completes full lottery lifecycle with all reminders and state transitions" do
    # STEP 1: Create lottery in draft state with Abholerpaket
    freeze_time(Time.zone.parse("2025-01-15 10:00:00"))

    sign_in(owner)
    post "/vzekc-verlosung/lotteries.json",
         params: {
           title: "Hardware Verlosung Januar 2025",
           category_id: category.id,
           duration_days: 14,
           abholerpaket_title: "Mein behalten System",
           packets: [{ title: "GPU Paket" }, { title: "CPU Paket" }, { title: "RAM Paket" }],
         }

    expect(response.status).to eq(200), "Expected 200 but got #{response.status}: #{response.body}"
    lottery_topic = Topic.find(response.parsed_body["main_topic"]["id"])
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: lottery_topic.id)

    expect(lottery.state).to eq("draft")
    expect(lottery.duration_days).to eq(14)

    # Verify Abholerpaket was created
    all_packets = VzekcVerlosung::LotteryPacket.where(lottery_id: lottery.id).order(:ordinal)
    expect(all_packets.count).to eq(4) # 1 Abholerpaket + 3 user packets

    abholerpaket = all_packets.first
    expect(abholerpaket.ordinal).to eq(0)
    expect(abholerpaket.title).to eq("Mein behalten System")
    expect(abholerpaket.abholerpaket).to eq(true)
    expect(abholerpaket.winner_user_id).to eq(owner.id)
    expect(abholerpaket.won_at).to be_present
    expect(abholerpaket.collected_at).to be_present # Automatically marked as collected
    expect(abholerpaket.erhaltungsbericht_required).to eq(true)

    # Verify all posts exist (1 main + 1 abholerpaket + 3 user packets)
    all_posts = Post.where(topic_id: lottery_topic.id).where("post_number > 1").order(:post_number)
    expect(all_posts.count).to eq(4)

    # Get user packet posts (excluding Abholerpaket)
    packet_posts = all_posts[1..3]

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
    # Note: "text" must match the packet title (without "Paket X:" prefix)
    mock_results = {
      "rngSeed" => "test-seed-12345",
      "drawingTimestamp" => Time.zone.now.iso8601,
      "drawings" => [
        {
          "text" => "GPU Paket",
          "winner" => participant1.username,
          "participants" => [{ "name" => participant1.username, "tickets" => 2 }],
        },
        {
          "text" => "CPU Paket",
          "winner" => participant2.username,
          "participants" => [{ "name" => participant2.username, "tickets" => 1 }],
        },
        {
          "text" => "RAM Paket",
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

    # Verify all packets have winners (excluding Abholerpaket which already has owner)
    user_packets =
      VzekcVerlosung::LotteryPacket
        .where(lottery_id: lottery.id)
        .where(abholerpaket: false)
        .order("posts.post_number")
        .joins(:post)
    expect(user_packets.count).to eq(3)
    expect(user_packets.all?(&:has_winner?)).to be true
    expect(user_packets.map { |p| p.winner.username }).to contain_exactly(
      participant1.username,
      participant2.username,
      participant3.username,
    )

    # STEP 9: Check history - all won, Abholerpaket collected, no erhaltungsberichte yet
    get "/vzekc-verlosung/history.json"
    expect(response.status).to eq(200)

    history = response.parsed_body
    expect(history["packets"].length).to eq(4) # Abholerpaket + 3 user packets

    # Verify Abholerpaket in history
    abholerpaket_history = history["packets"].find { |p| p["title"] == "Mein behalten System" }
    expect(abholerpaket_history).to be_present
    expect(abholerpaket_history["winner"]["username"]).to eq(owner.username)
    expect(abholerpaket_history["collected_at"]).to be_present # Already collected
    expect(abholerpaket_history["erhaltungsbericht"]).to be_nil

    # Verify user packets
    user_packets_history = history["packets"].reject { |p| p["title"] == "Mein behalten System" }
    expect(user_packets_history.length).to eq(3)

    user_packets_history.each do |packet_data|
      expect(packet_data["winner"]).to be_present
      expect(packet_data["collected_at"]).to be_nil
      expect(packet_data["erhaltungsbericht"]).to be_nil
    end

    # STEP 10: Erhaltungsbericht reminder for Abholerpaket
    # Note: Reminder fires on multiples of 7 days after collection
    # Abholerpaket collected at creation (2025-01-15 10:00)
    # Day 7: 2025-01-22 (before drawing), Day 14: 2025-01-29 (before drawing)
    # Day 21: 2025-02-05 (after drawing on 2025-02-02) - use this
    abholerpaket.reload
    freeze_time(abholerpaket.collected_at + 21.days)

    pm_count_before = Topic.where(archetype: Archetype.private_message).count

    Jobs::VzekcVerlosungErhaltungsberichtReminder.new.execute({})

    # Owner should receive reminder for Abholerpaket
    # Find PM created AFTER the drawing
    owner_erhaltungsbericht_pm =
      Topic
        .where(archetype: Archetype.private_message)
        .joins(:topic_allowed_users)
        .where(topic_allowed_users: { user_id: owner.id })
        .where("topics.created_at > ?", lottery.drawn_at)
        .order(created_at: :desc)
        .first

    expect(owner_erhaltungsbericht_pm).to be_present
    expect(owner_erhaltungsbericht_pm.title.downcase).to include("report").or include("reception")

    # STEP 11: Owner creates Erhaltungsbericht for Abholerpaket
    freeze_time(abholerpaket.collected_at + 22.days)

    sign_in(owner)
    post "/vzekc-verlosung/packets/#{abholerpaket.post_id}/create-erhaltungsbericht.json"
    expect(response.status).to eq(200)

    erhaltungsbericht_data = response.parsed_body
    expect(erhaltungsbericht_data["topic_url"]).to be_present

    abholerpaket.reload
    expect(abholerpaket.erhaltungsbericht_topic_id).to be_present

    abholerpaket_erhaltungsbericht_topic = Topic.find(abholerpaket.erhaltungsbericht_topic_id)
    expect(abholerpaket_erhaltungsbericht_topic.category_id).to eq(erhaltungsberichte_category.id)
    expect(abholerpaket_erhaltungsbericht_topic.user_id).to eq(owner.id)

    # STEP 12: Uncollected reminder fires 7 days after drawing (user packets)
    freeze_time(lottery.drawn_at + 7.days)

    pm_count_before = Topic.where(archetype: Archetype.private_message).count

    Jobs::VzekcVerlosungUncollectedReminder.new.execute({})

    expect(Topic.where(archetype: Archetype.private_message).count).to eq(pm_count_before + 1)

    uncollected_pm =
      Topic.where(archetype: Archetype.private_message).order(created_at: :desc).first
    expect(uncollected_pm.title).to include("3") # 3 uncollected user packets
    expect(uncollected_pm.title.downcase).to include("received").or include("collected")

    # STEP 13: Mark first packet as collected
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
    # 2 user packets uncollected (Abholerpaket was already collected)
    uncollected_count =
      history["packets"]
        .reject { |p| p["title"] == "Mein behalten System" }
        .count { |p| p["collected_at"].nil? }
    expect(uncollected_count).to eq(2)

    # STEP 14: Uncollected reminder 14 days after drawing (7 days later)
    freeze_time(lottery.drawn_at + 14.days)

    pm_count_before = Topic.where(archetype: Archetype.private_message).count

    Jobs::VzekcVerlosungUncollectedReminder.new.execute({})

    expect(Topic.where(archetype: Archetype.private_message).count).to eq(pm_count_before + 1)

    uncollected_pm2 =
      Topic.where(archetype: Archetype.private_message).order(created_at: :desc).first
    expect(uncollected_pm2.title).to include("2")

    # STEP 15: Erhaltungsbericht reminder 7 days after collection
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

    # STEP 16: Create erhaltungsbericht for first packet
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

    # STEP 17: Collect remaining packets
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

    # STEP 18: Create erhaltungsberichte for remaining packets
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

    # STEP 19: Delete an erhaltungsbericht - verify packet state reverts
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

    # STEP 20: Recreate erhaltungsbericht - should work and set new ID
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

    expect(history["packets"].length).to eq(4) # Abholerpaket + 3 user packets
    expect(history["packets"].all? { |p| p["winner"].present? }).to be true
    expect(history["packets"].all? { |p| p["collected_at"].present? }).to be true
    expect(history["packets"].all? { |p| p["erhaltungsbericht"].present? }).to be true
  end

  it "completes full lottery lifecycle WITHOUT Abholerpaket" do
    # STEP 1: Create lottery without Abholerpaket
    freeze_time(Time.zone.parse("2025-01-15 10:00:00"))

    sign_in(owner)
    post "/vzekc-verlosung/lotteries.json",
         params: {
           title: "Hardware Verlosung Januar 2025 (No Abholerpaket)",
           category_id: category.id,
           duration_days: 14,
           has_abholerpaket: false,
           packets: [{ title: "GPU Paket" }, { title: "CPU Paket" }, { title: "RAM Paket" }],
         }

    expect(response.status).to eq(200), "Expected 200 but got #{response.status}: #{response.body}"
    lottery_topic = Topic.find(response.parsed_body["main_topic"]["id"])
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: lottery_topic.id)

    expect(lottery.state).to eq("draft")
    expect(lottery.duration_days).to eq(14)

    # Verify NO Abholerpaket was created
    all_packets = VzekcVerlosung::LotteryPacket.where(lottery_id: lottery.id).order(:ordinal)
    expect(all_packets.count).to eq(3) # Only 3 user packets, no Abholerpaket

    # Verify no Abholerpaket exists
    abholerpaket = all_packets.find { |p| p.abholerpaket }
    expect(abholerpaket).to be_nil

    # Verify all posts exist (1 main + 3 user packets, no Abholerpaket post)
    all_posts = Post.where(topic_id: lottery_topic.id).where("post_number > 1").order(:post_number)
    expect(all_posts.count).to eq(3)

    packet_posts = all_posts.to_a

    # STEP 2: Publish lottery
    freeze_time(Time.zone.parse("2025-01-18 09:00:00"))

    sign_in(owner)
    put "/vzekc-verlosung/lotteries/#{lottery_topic.id}/publish.json"
    expect(response.status).to eq(204)

    lottery.reload
    expect(lottery.state).to eq("active")

    # STEP 3: Participants buy tickets for different packets
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

    expect(VzekcVerlosung::LotteryTicket.count).to eq(3)

    # STEP 4: Lottery ends
    freeze_time(lottery.ends_at + 2.hours)

    expect(VzekcVerlosung::Lottery.ready_to_draw).to include(lottery)

    # STEP 5: Draw winners
    freeze_time(lottery.ends_at + 1.day + 2.hours)

    sign_in(owner)
    get "/vzekc-verlosung/lotteries/#{lottery_topic.id}/drawing-data.json"
    expect(response.status).to eq(200)

    # Note: "text" must match the packet title (without "Paket X:" prefix)
    mock_results = {
      "rngSeed" => "test-seed-67890",
      "drawingTimestamp" => Time.zone.now.iso8601,
      "drawings" => [
        {
          "text" => "GPU Paket",
          "winner" => participant1.username,
          "participants" => [{ "name" => participant1.username, "tickets" => 1 }],
        },
        {
          "text" => "CPU Paket",
          "winner" => participant2.username,
          "participants" => [{ "name" => participant2.username, "tickets" => 1 }],
        },
        {
          "text" => "RAM Paket",
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

    # STEP 6: Verify no Erhaltungsbericht reminders sent to owner (no Abholerpaket)
    freeze_time(lottery.drawn_at + 7.days)

    pm_count_before = Topic.where(archetype: Archetype.private_message).count

    Jobs::VzekcVerlosungErhaltungsberichtReminder.new.execute({})

    # Owner should NOT receive any Erhaltungsbericht reminders (no Abholerpaket)
    owner_pms_after_job =
      Topic
        .where(archetype: Archetype.private_message)
        .joins(:topic_allowed_users)
        .where(topic_allowed_users: { user_id: owner.id })
        .where("topics.created_at > ?", lottery.drawn_at)
        .count

    # Owner should not have received new PM for Erhaltungsbericht
    expect(owner_pms_after_job).to eq(0)

    # STEP 7: Mark all packets as collected
    freeze_time(lottery.drawn_at + 8.days)

    sign_in(owner)
    packet_posts.each do |packet_post|
      post "/vzekc-verlosung/packets/#{packet_post.id}/mark-collected.json"
      expect(response.status).to eq(200)
    end

    # STEP 8: Create erhaltungsberichte for all packets
    freeze_time(lottery.drawn_at + 9.days)

    sign_in(participant1)
    post "/vzekc-verlosung/packets/#{packet_posts[0].id}/create-erhaltungsbericht.json"
    expect(response.status).to eq(200)

    sign_in(participant2)
    post "/vzekc-verlosung/packets/#{packet_posts[1].id}/create-erhaltungsbericht.json"
    expect(response.status).to eq(200)

    sign_in(participant3)
    post "/vzekc-verlosung/packets/#{packet_posts[2].id}/create-erhaltungsbericht.json"
    expect(response.status).to eq(200)

    # Final history check - only 3 packets, no Abholerpaket
    get "/vzekc-verlosung/history.json"
    history = response.parsed_body

    expect(history["packets"].length).to eq(3) # Only 3 user packets
    expect(history["packets"].all? { |p| p["winner"].present? }).to be true
    expect(history["packets"].all? { |p| p["collected_at"].present? }).to be true
    expect(history["packets"].all? { |p| p["erhaltungsbericht"].present? }).to be true

    # Verify no Abholerpaket in history
    abholerpaket_in_history = history["packets"].find { |p| p["abholerpaket"] == true }
    expect(abholerpaket_in_history).to be_nil
  end

  it "correctly handles donation topics with lottery created" do
    # STEP 1: Create a donation
    donation =
      VzekcVerlosung::Donation.create!(postcode: "10115", creator_user_id: owner.id, state: "draft")

    post_creator =
      PostCreator.new(
        owner,
        title: "Hardware to give away in 10115",
        raw: "Some hardware available for pickup",
        category: category.id,
        skip_validations: true,
      )
    donation_topic_post = post_creator.create
    donation.update!(topic_id: donation_topic_post.topic_id, state: "picked_up")

    # STEP 2: Check donation_data before lottery creation
    sign_in(owner)
    get "/t/#{donation_topic_post.topic_id}.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body.dig("post_stream", "posts", 0, "donation_data")).to be_present
    expect(
      response.parsed_body.dig("post_stream", "posts", 0, "donation_data", "lottery_id"),
    ).to be_nil
    expect(response.parsed_body.dig("post_stream", "posts", 0, "is_donation_post")).to eq(true)

    # STEP 3: Create lottery from donation
    post "/vzekc-verlosung/lotteries.json",
         params: {
           title: "Lottery from donation",
           category_id: category.id,
           duration_days: 7,
           donation_id: donation.id,
           packets: [{ title: "Hardware Bundle" }],
         }

    expect(response.status).to eq(200)
    lottery_response = response.parsed_body
    lottery_topic_id = lottery_response["main_topic"]["id"]
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: lottery_topic_id)

    # Verify donation now has lottery_id
    donation.reload
    expect(donation.lottery).to eq(lottery)

    # STEP 4: Check donation_data after lottery creation
    get "/t/#{donation_topic_post.topic_id}.json"
    expect(response.status).to eq(200)
    donation_data = response.parsed_body.dig("post_stream", "posts", 0, "donation_data")
    expect(donation_data).to be_present
    expect(donation_data["lottery_id"]).to eq(lottery.id)

    # STEP 5: Verify donation topic still shows is_donation_post
    # Donation topics remain donation topics even after lottery creation
    expect(response.parsed_body.dig("post_stream", "posts", 0, "is_donation_post")).to eq(true)
    expect(response.parsed_body.dig("post_stream", "posts", 0, "is_lottery_intro")).to be_falsey

    # STEP 6: Verify the lottery topic shows is_lottery_intro but NOT is_donation_post
    get "/t/#{lottery_topic_id}.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body.dig("post_stream", "posts", 0, "is_donation_post")).to be_falsey
    expect(response.parsed_body.dig("post_stream", "posts", 0, "is_lottery_intro")).to eq(true)
  end
end
