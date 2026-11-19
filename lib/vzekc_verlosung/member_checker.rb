# frozen_string_literal: true

module VzekcVerlosung
  module MemberChecker
    # Check if user belongs to one of the configured member groups
    # (e.g. full and supporting members). Returns true when no configured
    # group exists, so an unconfigured site treats everyone as a member.
    #
    # @param user [User] The user to check
    # @return [Boolean] true if user is in any of the configured member groups
    def self.active_member?(user)
      return false unless user

      group_names = SiteSetting.vzekc_verlosung_members_group_names.split("|").map(&:strip)
      group_ids = Group.where(name: group_names.compact_blank).pluck(:id)
      return true if group_ids.empty?

      GroupUser.exists?(group_id: group_ids, user_id: user.id)
    end
  end
end
