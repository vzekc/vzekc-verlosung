# frozen_string_literal: true

require "rails_helper"

describe VzekcVerlosung::RequiresLotteryParticipant do
  fab!(:member_group) { Fabricate(:group, name: "vereinsmitglieder") }
  fab!(:member, :user)
  fab!(:supporting_member, :user)
  fab!(:admin)

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_members_group_names = "vereinsmitglieder"
    member_group.add(member)
  end

  context "as a member of a configured group" do
    before { sign_in(member) }

    it "allows the lottery pages" do
      get "/vzekc-verlosung/active.json"
      expect(response.status).to eq(200)

      get "/vzekc-verlosung/active-donations.json"
      expect(response.status).to eq(200)
    end
  end

  context "as a user outside the configured groups" do
    before { sign_in(supporting_member) }

    it "denies the lottery pages" do
      get "/vzekc-verlosung/active.json"
      expect(response.status).to eq(403)

      get "/vzekc-verlosung/active-donations.json"
      expect(response.status).to eq(403)

      get "/vzekc-verlosung/history.json"
      expect(response.status).to eq(403)
    end

    it "denies drawing tickets" do
      post "/vzekc-verlosung/tickets.json", params: { post_id: 1 }
      expect(response.status).to eq(403)
    end

    it "denies creating lotteries" do
      post "/vzekc-verlosung/lotteries.json", params: { title: "Test" }
      expect(response.status).to eq(403)
    end

    it "is not marked as participant on the current user" do
      get "/session/current.json"
      expect(response.parsed_body["current_user"]["vzekc_verlosung_can_participate"]).to eq(false)
    end

    context "after adding the user's group to the setting" do
      fab!(:supporting_group) { Fabricate(:group, name: "foerdermitglieder") }

      before do
        supporting_group.add(supporting_member)
        SiteSetting.vzekc_verlosung_members_group_names = "vereinsmitglieder|foerdermitglieder"
      end

      it "allows the lottery pages" do
        get "/vzekc-verlosung/active.json"
        expect(response.status).to eq(200)
      end
    end
  end

  context "when not logged in" do
    it "is not a participant" do
      expect(Guardian.new.can_participate_in_lotteries?).to eq(false)
    end
  end

  context "as staff outside the configured groups" do
    before { sign_in(admin) }

    it "allows the lottery pages" do
      get "/vzekc-verlosung/active.json"
      expect(response.status).to eq(200)
    end
  end
end
