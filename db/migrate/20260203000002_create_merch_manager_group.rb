# frozen_string_literal: true

class CreateMerchManagerGroup < ActiveRecord::Migration[7.2]
  def up
    group_name = "MerchManager"

    # Create the group if it doesn't exist
    group =
      Group.find_by(name: group_name) ||
        Group.create!(
          name: group_name,
          visibility_level: Group.visibility_levels[:staff],
          mentionable_level: Group::ALIAS_LEVELS[:only_admins],
          messageable_level: Group::ALIAS_LEVELS[:only_admins],
          full_name: "Merch Packet Handlers",
        )

    # Add users to the group
    %w[hans Cartouce].each do |username|
      user = User.find_by(username: username)
      group.add(user) if user && !group.users.include?(user)
    end

    # Configure the plugin to use this group
    SiteSetting.vzekc_verlosung_merch_handlers_group_name = group_name
  end

  def down
    SiteSetting.vzekc_verlosung_merch_handlers_group_name = ""
    # Don't delete the group on rollback - it may have been manually configured
  end
end
