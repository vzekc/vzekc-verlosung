# frozen_string_literal: true

module VzekcVerlosung
  module MemberChecker
    # Check if user is an active member of the configured group
    # Returns true if no group is configured (allows all)
    #
    # @param user [User] The user to check
    # @return [Boolean] true if user is a member of the configured group
    def self.active_member?(user)
      return false unless user

      group_name = SiteSetting.vzekc_verlosung_members_group_name
      return true if group_name.blank?

      group = Group.find_by(name: group_name)
      return true unless group

      group.users.exists?(user.id)
    end
  end
end
