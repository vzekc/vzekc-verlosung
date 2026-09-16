# frozen_string_literal: true

RSpec.describe VzekcVerlosung::DrawLottery do
  fab!(:owner) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:participant) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:other_participant) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:category)

  before { SiteSetting.vzekc_verlosung_enabled = true }

  def create_lottery(auto_draw: true, drawing_mode: "automatic")
    result =
      VzekcVerlosung::CreateLottery.call(
        params: {
          title: "Auto Draw Lottery",
          raw: "Lottery content",
          category_id: category.id,
          duration_days: 14,
          has_abholerpaket: false,
          drawing_mode: drawing_mode,
          auto_draw: auto_draw,
          packets: [
            { title: "Packet 1", raw: "Content 1" },
            { title: "Packet 2", raw: "Content 2" },
          ],
        },
        user: owner,
        guardian: Guardian.new(owner),
      )
    expect(result).to be_success
    result.lottery
  end

  def owner_pm_titles
    Topic
      .where(archetype: Archetype.private_message)
      .joins(:topic_allowed_users)
      .where(topic_allowed_users: { user_id: owner.id })
      .pluck(:title)
  end

  describe ".auto_draw!" do
    context "with an ended lottery that has tickets" do
      let!(:lottery) { create_lottery }
      let(:packet_with_tickets) { lottery.lottery_packets.order(:ordinal).first }
      let(:packet_without_tickets) { lottery.lottery_packets.order(:ordinal).last }

      before do
        VzekcVerlosung::LotteryTicket.create!(
          post_id: packet_with_tickets.post_id,
          user_id: participant.id,
        )
        VzekcVerlosung::LotteryTicket.create!(
          post_id: packet_with_tickets.post_id,
          user_id: other_participant.id,
        )
        lottery.update!(ends_at: 1.minute.ago)
      end

      it "draws the lottery and stores the results" do
        expect(described_class.auto_draw!(lottery)).to eq(true)

        lottery.reload
        expect(lottery.state).to eq("finished")
        expect(lottery.drawn_at).to be_present
        expect(lottery.results["drawings"].length).to eq(2)
        expect(lottery.results["rngSeed"]).to be_present
      end

      it "produces the same results as the verification drawing" do
        expected =
          VzekcVerlosung::JavascriptLotteryDrawer.draw(described_class.drawing_data(lottery))

        described_class.auto_draw!(lottery)

        expect(lottery.reload.results["drawings"]).to eq(expected["drawings"])
      end

      it "marks winners and packets" do
        described_class.auto_draw!(lottery)

        packet_with_tickets.reload
        packet_without_tickets.reload
        expect(packet_with_tickets.state).to eq("drawn")
        winner_ids = packet_with_tickets.winners.map(&:id)
        expect(winner_ids.length).to eq(1)
        expect([participant.id, other_participant.id]).to include(winner_ids.first)
        expect(packet_without_tickets.state).to eq("no_tickets")
      end

      it "notifies the winner, the non-winner, and the owner" do
        described_class.auto_draw!(lottery)

        expect(VzekcVerlosung::NotificationLog.where(notification_type: "lottery_won").count).to eq(
          1,
        )
        expect(VzekcVerlosung::NotificationLog.where(notification_type: "did_not_win").count).to eq(
          1,
        )
        expect(
          VzekcVerlosung::NotificationLog.where(
            notification_type: "lottery_auto_drawn",
            recipient_user_id: owner.id,
            success: true,
          ).count,
        ).to eq(1)
        expect(owner_pm_titles).to include(
          I18n.t("vzekc_verlosung.notifications.lottery_auto_drawn.title"),
        )
      end

      it "does nothing when the lottery is already drawn" do
        described_class.auto_draw!(lottery)
        results = lottery.reload.results

        expect(described_class.auto_draw!(lottery.reload)).to eq(false)
        expect(lottery.reload.results).to eq(results)
      end

      it "leaves the lottery ready to draw when the drawing fails" do
        allow(VzekcVerlosung::JavascriptLotteryDrawer).to receive(:draw).and_raise(
          MiniRacer::ScriptTerminatedError,
        )

        expect(described_class.auto_draw!(lottery)).to eq(false)

        lottery.reload
        expect(lottery.state).to eq("active")
        expect(lottery.drawn_at).to be_nil
      end
    end

    context "with an ended lottery without tickets" do
      let!(:lottery) { create_lottery }

      before { lottery.update!(ends_at: 1.minute.ago) }

      it "finishes the lottery without participants and notifies the owner" do
        expect(described_class.auto_draw!(lottery)).to eq(true)

        lottery.reload
        expect(lottery.no_participants?).to eq(true)
        expect(
          VzekcVerlosung::NotificationLog.where(
            notification_type: "no_participants_reminder",
            recipient_user_id: owner.id,
          ).count,
        ).to eq(1)
      end
    end

    context "when the lottery has not ended" do
      let!(:lottery) { create_lottery }

      it "does nothing" do
        expect(described_class.auto_draw!(lottery)).to eq(false)
        expect(lottery.reload.state).to eq("active")
      end
    end

    context "when the lottery is not configured to draw on end" do
      let!(:lottery) { create_lottery(auto_draw: false) }

      before do
        VzekcVerlosung::LotteryTicket.create!(
          post_id: lottery.lottery_packets.first.post_id,
          user_id: participant.id,
        )
        lottery.update!(ends_at: 1.minute.ago)
      end

      it "does nothing" do
        expect(described_class.auto_draw!(lottery)).to eq(false)
        expect(lottery.reload.drawn_at).to be_nil
      end
    end
  end

  describe ".apply_results!" do
    let!(:lottery) { create_lottery(auto_draw: false, drawing_mode: "manual") }
    let(:packet) { lottery.lottery_packets.order(:ordinal).first }
    let(:other_packet) { lottery.lottery_packets.order(:ordinal).last }

    before do
      VzekcVerlosung::LotteryTicket.create!(post_id: packet.post_id, user_id: participant.id)
      lottery.update!(ends_at: 1.minute.ago)
    end

    it "stores manual results and marks packets" do
      results = {
        "manual" => true,
        "drawings" => [
          { "text" => packet.title, "quantity" => 1, "winners" => [participant.username] },
        ],
        "packets" => [{ "id" => packet.post_id, "title" => packet.title }],
        "drawn_at" => Time.zone.now.iso8601,
      }

      described_class.apply_results!(lottery, results)

      lottery.reload
      expect(lottery.state).to eq("finished")
      expect(lottery.results["manual"]).to eq(true)
      expect(packet.reload.winners.map(&:id)).to eq([participant.id])
      expect(other_packet.reload.state).to eq("no_tickets")
    end

    it "refuses to draw a lottery that has already been drawn" do
      results = {
        "manual" => true,
        "drawings" => [
          { "text" => packet.title, "quantity" => 1, "winners" => [participant.username] },
        ],
        "packets" => [{ "id" => packet.post_id, "title" => packet.title }],
        "drawn_at" => Time.zone.now.iso8601,
      }
      described_class.apply_results!(lottery, results)

      expect { described_class.apply_results!(lottery.reload, results) }.to raise_error(
        described_class::AlreadyDrawnError,
      )
      expect(packet.reload.lottery_packet_winners.count).to eq(1)
    end
  end
end
