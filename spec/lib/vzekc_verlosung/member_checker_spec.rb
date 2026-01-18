# frozen_string_literal: true

require "rails_helper"

RSpec.describe VzekcVerlosung::MemberChecker do
  fab!(:member_group) { Fabricate(:group, name: "vereinsmitglieder") }
  fab!(:member_user, :user)
  fab!(:non_member_user, :user)

  before do
    member_group.add(member_user)
    SiteSetting.vzekc_verlosung_members_group_name = "vereinsmitglieder"
  end

  describe ".active_member?" do
    context "with configured group" do
      it "returns true for users in the group" do
        expect(described_class.active_member?(member_user)).to be true
      end

      it "returns false for users not in the group" do
        expect(described_class.active_member?(non_member_user)).to be false
      end

      it "returns false for nil user" do
        expect(described_class.active_member?(nil)).to be false
      end
    end

    context "with blank group name setting" do
      before { SiteSetting.vzekc_verlosung_members_group_name = "" }

      it "returns true for any user" do
        expect(described_class.active_member?(member_user)).to be true
        expect(described_class.active_member?(non_member_user)).to be true
      end

      it "returns false for nil user" do
        expect(described_class.active_member?(nil)).to be false
      end
    end

    context "with non-existent group name" do
      before { SiteSetting.vzekc_verlosung_members_group_name = "nonexistent_group" }

      it "returns true for any user" do
        expect(described_class.active_member?(member_user)).to be true
        expect(described_class.active_member?(non_member_user)).to be true
      end

      it "returns false for nil user" do
        expect(described_class.active_member?(nil)).to be false
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
