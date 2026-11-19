# frozen_string_literal: true

require "rails_helper"

RSpec.describe VzekcVerlosung::MemberChecker do
  fab!(:member_group) { Fabricate(:group, name: "vereinsmitglieder") }
  fab!(:supporting_group) { Fabricate(:group, name: "foerdermitglieder") }
  fab!(:member_user, :user)
  fab!(:supporting_user, :user)
  fab!(:non_member_user, :user)

  before do
    member_group.add(member_user)
    supporting_group.add(supporting_user)
    SiteSetting.vzekc_verlosung_members_group_names = "vereinsmitglieder|foerdermitglieder"
  end

  describe ".active_member?" do
    context "with configured groups" do
      it "returns true for users in the first group" do
        expect(described_class.active_member?(member_user)).to be true
      end

      it "returns true for users in another configured group" do
        expect(described_class.active_member?(supporting_user)).to be true
      end

      it "returns false for users in none of the groups" do
        expect(described_class.active_member?(non_member_user)).to be false
      end

      it "returns false for nil user" do
        expect(described_class.active_member?(nil)).to be false
      end
    end

    context "with blank group names setting" do
      before { SiteSetting.vzekc_verlosung_members_group_names = "" }

      it "returns true for any user" do
        expect(described_class.active_member?(member_user)).to be true
        expect(described_class.active_member?(non_member_user)).to be true
      end

      it "returns false for nil user" do
        expect(described_class.active_member?(nil)).to be false
      end
    end

    context "with only non-existent group names" do
      before { SiteSetting.vzekc_verlosung_members_group_names = "nonexistent_group" }

      it "returns true for any user" do
        expect(described_class.active_member?(member_user)).to be true
        expect(described_class.active_member?(non_member_user)).to be true
      end
    end

    context "when user is removed from group" do
      it "returns false after removal" do
        expect(described_class.active_member?(member_user)).to be true
        member_group.remove(member_user)
        expect(described_class.active_member?(member_user)).to be false
      end
    end
  end
end
