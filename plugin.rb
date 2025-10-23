# frozen_string_literal: true

# name: vzekc-verlosung
# about: Discourse-Plugin zur Organisation von Hardwareverlosungen
# meta_topic_id: TODO
# version: 0.0.1
# authors: Hans Hübner
# url: https://github.com/vzekc/vzekc-verlosung
# required_version: 2.7.0

enabled_site_setting :vzekc_verlosung_enabled

module ::VzekcVerlosung
  PLUGIN_NAME = "vzekc-verlosung"
end

require_relative "lib/vzekc_verlosung/engine"

after_initialize do
  # Services and controllers are auto-loaded from app/ directories
  # No manual requires needed

  # Register custom field for lottery packet posts
  register_post_custom_field_type("is_lottery_packet", :boolean)

  # Add custom field to post serializer
  add_to_serializer(:post, :is_lottery_packet) do
    object.custom_fields["is_lottery_packet"] == true
  end
end
