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

register_svg_icon "trophy"
register_svg_icon "dice"
register_svg_icon "receipt"
register_svg_icon "ticket"
register_svg_icon "tag"
register_svg_icon "tags"
register_svg_icon "clipboard-list"
register_svg_icon "bullhorn"
register_svg_icon "times-circle"
register_svg_icon "clock"

module ::VzekcVerlosung
  PLUGIN_NAME = "vzekc-verlosung"
end

require_relative "lib/vzekc_verlosung/engine"
require_relative "lib/vzekc_verlosung/guardian_extensions"

after_initialize do
  # Add custom notification types to the Notification.types enum
  # Since Enum extends Hash, we can add new types directly
  Notification.types[:vzekc_verlosung_published] = 810
  Notification.types[:vzekc_verlosung_drawn] = 811
  Notification.types[:vzekc_verlosung_won] = 812
  Notification.types[:vzekc_verlosung_ticket_bought] = 813
  Notification.types[:vzekc_verlosung_ticket_returned] = 814
  Notification.types[:vzekc_verlosung_did_not_win] = 815
  Notification.types[:vzekc_verlosung_ending_tomorrow] = 816
  Notification.types[:vzekc_verlosung_uncollected_reminder] = 817

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
  register_post_custom_field_type("lottery_winner", :string)
  register_post_custom_field_type("packet_collected_at", :datetime)
  register_post_custom_field_type("erhaltungsbericht_topic_id", :integer)

  # Register custom fields for lottery topics
  # lottery_state: "draft", "active", or "finished"
  register_topic_custom_field_type("lottery_state", :string)
  # lottery_ends_at: DateTime when the lottery ends (set when published)
  register_topic_custom_field_type("lottery_ends_at", :datetime)
  # lottery_results: JSON containing full drawing results
  register_topic_custom_field_type("lottery_results", :json)
  # lottery_drawn_at: DateTime when the drawing was performed
  register_topic_custom_field_type("lottery_drawn_at", :datetime)

  # Preload lottery custom fields for topic lists to prevent N+1 queries
  add_preloaded_topic_list_custom_field("lottery_state")
  add_preloaded_topic_list_custom_field("lottery_ends_at")

  # Add helper methods to Topic class to safely access lottery fields
  add_to_class(:topic, :lottery_state) { custom_fields["lottery_state"] }

  add_to_class(:topic, :lottery_ends_at) do
    value = custom_fields["lottery_ends_at"]
    value.is_a?(String) ? Time.zone.parse(value) : value
  end

  add_to_class(:topic, :lottery_draft?) { lottery_state == "draft" }

  add_to_class(:topic, :lottery_active?) { lottery_state == "active" }

  add_to_class(:topic, :lottery_finished?) { lottery_state == "finished" }

  add_to_class(:topic, :lottery_results) { custom_fields["lottery_results"] }

  add_to_class(:topic, :lottery_drawn_at) do
    value = custom_fields["lottery_drawn_at"]
    value.is_a?(String) ? Time.zone.parse(value) : value
  end

  add_to_class(:topic, :lottery_drawn?) { lottery_results.present? }

  # Add custom fields to post serializer
  add_to_serializer(:post, :is_lottery_packet) { object.custom_fields["is_lottery_packet"] == true }

  add_to_serializer(:post, :is_lottery_intro) { object.custom_fields["is_lottery_intro"] == true }

  add_to_serializer(:post, :lottery_winner) { object.custom_fields["lottery_winner"] }

  # Include collection timestamp for lottery owner and winner
  add_to_serializer(:post, :packet_collected_at) do
    return nil unless object.custom_fields["is_lottery_packet"] == true

    # Show to lottery owner, staff, or winner
    topic = object.topic
    winner_username = object.custom_fields["lottery_winner"]
    is_winner = winner_username.present? && scope.user&.username == winner_username
    return nil unless topic && (scope.is_staff? || topic.user_id == scope.user&.id || is_winner)

    value = object.custom_fields["packet_collected_at"]
    value.is_a?(String) ? Time.zone.parse(value) : value
  end

  add_to_serializer(:post, :include_packet_collected_at?) do
    object.custom_fields["is_lottery_packet"] == true
  end

  # Include erhaltungsbericht topic ID
  add_to_serializer(:post, :erhaltungsbericht_topic_id) do
    object.custom_fields["erhaltungsbericht_topic_id"]&.to_i
  end

  add_to_serializer(:post, :include_erhaltungsbericht_topic_id?) do
    object.custom_fields["is_lottery_packet"] == true
  end

  # Add custom fields to topic serializers (using helper methods)
  add_to_serializer(:topic_view, :lottery_state) { object.topic.lottery_state }

  add_to_serializer(:topic_view, :lottery_ends_at) { object.topic.lottery_ends_at }

  add_to_serializer(:topic_view, :lottery_results) { object.topic.lottery_results }

  add_to_serializer(:topic_view, :lottery_drawn_at) { object.topic.lottery_drawn_at }

  add_to_serializer(:topic_list_item, :lottery_state) { object.lottery_state }

  add_to_serializer(:topic_list_item, :lottery_ends_at) { object.lottery_ends_at }
end
