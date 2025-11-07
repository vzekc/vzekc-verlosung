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
  Notification.types[:vzekc_verlosung_erhaltungsbericht_reminder] = 818

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
  # packet_post_id: Post ID of the packet in the lottery (for Erhaltungsberichte)
  register_topic_custom_field_type("packet_post_id", :integer)
  # packet_topic_id: Topic ID of the lottery (for Erhaltungsberichte)
  register_topic_custom_field_type("packet_topic_id", :integer)

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
  add_to_serializer(
    :post,
    :packet_collected_at,
    include_condition: -> { object.custom_fields["is_lottery_packet"] == true },
  ) do
    # Show to lottery owner, staff, or winner
    topic = object.topic
    winner_username = object.custom_fields["lottery_winner"]
    is_winner = winner_username.present? && scope.user&.username == winner_username
    return nil unless topic && (scope.is_staff? || topic.user_id == scope.user&.id || is_winner)

    value = object.custom_fields["packet_collected_at"]
    value.is_a?(String) ? Time.zone.parse(value) : value
  end

  # Include erhaltungsbericht topic ID (only if topic still exists)
  add_to_serializer(
    :post,
    :erhaltungsbericht_topic_id,
    include_condition: -> { object.custom_fields["is_lottery_packet"] == true },
  ) do
    topic_id = object.custom_fields["erhaltungsbericht_topic_id"]&.to_i
    return nil unless topic_id

    # Check if the topic still exists
    Topic.exists?(id: topic_id) ? topic_id : nil
  end

  # Add custom fields to topic serializers (using helper methods)
  add_to_serializer(:topic_view, :lottery_state) { object.topic.lottery_state }

  add_to_serializer(:topic_view, :lottery_ends_at) { object.topic.lottery_ends_at }

  add_to_serializer(:topic_view, :lottery_results) { object.topic.lottery_results }

  add_to_serializer(:topic_view, :lottery_drawn_at) { object.topic.lottery_drawn_at }

  add_to_serializer(:topic_list_item, :lottery_state) { object.lottery_state }

  add_to_serializer(:topic_list_item, :lottery_ends_at) { object.lottery_ends_at }

  # Include packet reference fields for Erhaltungsberichte
  add_to_serializer(:topic_view, :packet_post_id) do
    object.topic.custom_fields["packet_post_id"]&.to_i
  end

  add_to_serializer(:topic_view, :packet_topic_id) do
    object.topic.custom_fields["packet_topic_id"]&.to_i
  end

  # Whitelist packet reference parameters for topic creation
  add_permitted_post_create_param(:packet_post_id)
  add_permitted_post_create_param(:packet_topic_id)

  # Register callback to establish bidirectional link when Erhaltungsbericht is created
  on(:topic_created) do |topic, opts, user|
    # Debug logging
    Rails.logger.info "=== VzekcVerlosung topic_created callback ==="
    Rails.logger.info "Topic ID: #{topic.id}, Title: #{topic.title}"
    Rails.logger.info "User: #{user.username}"
    Rails.logger.info "Opts keys: #{opts.keys.inspect}"
    Rails.logger.info "packet_post_id in opts: #{opts[:packet_post_id].inspect}"
    Rails.logger.info "packet_topic_id in opts: #{opts[:packet_topic_id].inspect}"

    # Check if packet reference data is in opts (from composer)
    packet_post_id = opts[:packet_post_id]&.to_i
    packet_topic_id = opts[:packet_topic_id]&.to_i

    if packet_post_id.blank? || packet_topic_id.blank?
      Rails.logger.info "Exiting early: packet_post_id or packet_topic_id is blank"
      next
    end

    # Save packet reference to topic custom fields
    topic.custom_fields["packet_post_id"] = packet_post_id
    topic.custom_fields["packet_topic_id"] = packet_topic_id
    topic.save_custom_fields
    Rails.logger.info "Saved packet reference to topic custom fields"

    # Find the packet post
    packet_post = Post.find_by(id: packet_post_id, topic_id: packet_topic_id)
    unless packet_post
      Rails.logger.info "Exiting: packet post not found"
      next
    end
    Rails.logger.info "Found packet post #{packet_post.id}"

    # Verify it's a lottery packet
    unless packet_post.custom_fields["is_lottery_packet"] == true
      Rails.logger.info "Exiting: post is not a lottery packet"
      next
    end

    # Verify the user is the winner
    winner_username = packet_post.custom_fields["lottery_winner"]
    unless winner_username == user.username
      Rails.logger.info "Exiting: user #{user.username} is not the winner (winner is #{winner_username})"
      next
    end

    # Establish reverse link from packet to Erhaltungsbericht
    packet_post.custom_fields["erhaltungsbericht_topic_id"] = topic.id
    packet_post.save_custom_fields
    Rails.logger.info "Successfully saved erhaltungsbericht_topic_id #{topic.id} to packet post #{packet_post.id}"
  end
end
