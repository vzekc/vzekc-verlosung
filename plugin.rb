# frozen_string_literal: true

# name: vzekc-verlosung
# about: Discourse-Plugin zur Organisation von Hardwareverlosungen
# meta_topic_id: TODO
# version: 0.0.1
# authors: Hans Hübner
# url: https://github.com/vzekc/vzekc-verlosung
# required_version: 2.7.0

enabled_site_setting :vzekc_verlosung_enabled

register_asset "stylesheets/vzekc-verlosung.scss"

module ::VzekcVerlosung
  PLUGIN_NAME = "vzekc-verlosung"
end

require_relative "lib/vzekc_verlosung/engine"
require_relative "lib/vzekc_verlosung/guardian_extensions"

after_initialize do
  # Extend Guardian with custom permissions
  Guardian.include(VzekcVerlosung::GuardianExtensions)

  # Hook into can_create_post to check lottery draft status
  Guardian.class_eval do
    alias_method :original_can_create_post?, :can_create_post?

    def can_create_post?(topic)
      return false unless original_can_create_post?(topic)
      can_create_post_in_lottery_draft?(topic)
    end
  end

  # Services and controllers are auto-loaded from app/ directories
  # No manual requires needed

  # Register custom fields for lottery posts
  register_post_custom_field_type("is_lottery_packet", :boolean)
  register_post_custom_field_type("is_lottery_intro", :boolean)

  # Register custom field for lottery draft topics
  register_topic_custom_field_type("lottery_draft", :boolean)

  # Preload lottery_draft custom field for topic lists to prevent N+1 queries
  add_preloaded_topic_list_custom_field("lottery_draft")

  # Add helper method to Topic class to safely access lottery_draft
  add_to_class(:topic, :lottery_draft) do
    custom_fields["lottery_draft"] == true
  end

  # Add custom fields to post serializer
  add_to_serializer(:post, :is_lottery_packet) do
    object.custom_fields["is_lottery_packet"] == true
  end

  add_to_serializer(:post, :is_lottery_intro) do
    object.custom_fields["is_lottery_intro"] == true
  end

  # Add custom field to topic serializer (using helper method)
  add_to_serializer(:topic_view, :lottery_draft) do
    object.topic.lottery_draft
  end

  add_to_serializer(:topic_list_item, :lottery_draft) do
    object.lottery_draft
  end
end
