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

  # Register custom fields for lottery topics
  # lottery_state: "draft", "active", or "finished"
  register_topic_custom_field_type("lottery_state", :string)
  # lottery_ends_at: DateTime when the lottery ends (set when published)
  register_topic_custom_field_type("lottery_ends_at", :datetime)

  # Preload lottery custom fields for topic lists to prevent N+1 queries
  add_preloaded_topic_list_custom_field("lottery_state")
  add_preloaded_topic_list_custom_field("lottery_ends_at")

  # Add helper methods to Topic class to safely access lottery fields
  add_to_class(:topic, :lottery_state) do
    custom_fields["lottery_state"]
  end

  add_to_class(:topic, :lottery_ends_at) do
    value = custom_fields["lottery_ends_at"]
    value.is_a?(String) ? Time.zone.parse(value) : value
  end

  add_to_class(:topic, :lottery_draft?) do
    lottery_state == "draft"
  end

  add_to_class(:topic, :lottery_active?) do
    lottery_state == "active"
  end

  add_to_class(:topic, :lottery_finished?) do
    lottery_state == "finished"
  end

  # Add custom fields to post serializer
  add_to_serializer(:post, :is_lottery_packet) do
    object.custom_fields["is_lottery_packet"] == true
  end

  add_to_serializer(:post, :is_lottery_intro) do
    object.custom_fields["is_lottery_intro"] == true
  end

  # Add custom fields to topic serializers (using helper methods)
  add_to_serializer(:topic_view, :lottery_state) do
    object.topic.lottery_state
  end

  add_to_serializer(:topic_view, :lottery_ends_at) do
    object.topic.lottery_ends_at
  end

  add_to_serializer(:topic_list_item, :lottery_state) do
    object.lottery_state
  end

  add_to_serializer(:topic_list_item, :lottery_ends_at) do
    object.lottery_ends_at
  end
end
