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
register_asset "stylesheets/lottery-history.scss"

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
register_svg_icon "pen"
register_svg_icon "file"

module ::VzekcVerlosung
  PLUGIN_NAME = "vzekc-verlosung"
end

require_relative "lib/vzekc_verlosung/engine"
require_relative "lib/vzekc_verlosung/guardian_extensions"

after_initialize do
  # Register the lottery history route as a valid Ember route
  Discourse::Application.routes.append do
    get "/lottery-history" => "users#index", :constraints => { format: /(json|html)/ }
  end

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

  # Filter draft lotteries from topic lists for non-owners
  TopicQuery.add_custom_filter(:lottery_state) do |results, topic_query|
    user = topic_query.user

    # Filter out draft lotteries unless user is staff or owner
    results =
      results.where(
        "topics.id NOT IN (
        SELECT topic_id FROM vzekc_verlosung_lotteries
        WHERE state = 'draft'
        AND topic_id NOT IN (
          SELECT id FROM topics WHERE user_id = ?
        )
      )",
        user&.id || -1,
      )

    # Staff can see all drafts
    if user&.staff?
      results
    else
      results
    end
  end

  # Services and controllers are auto-loaded from app/ directories
  # No manual requires needed

  # Add associations to core Discourse models
  add_to_class(:topic, :lottery) { @lottery ||= VzekcVerlosung::Lottery.find_by(topic_id: id) }

  add_to_class(:post, :lottery_packet) do
    @lottery_packet ||= VzekcVerlosung::LotteryPacket.find_by(post_id: id)
  end

  # Add hybrid cleanup with DiscourseEvent hooks + foreign keys
  # Foreign keys handle hard deletes automatically, events allow custom logic
  on(:post_destroyed) do |post, opts, user|
    # Optional: Log or handle packet deletion
    packet = VzekcVerlosung::LotteryPacket.find_by(post_id: post.id)
    Rails.logger.info("Lottery packet deleted with post #{post.id}: #{packet.title}") if packet
  end

  on(:topic_destroyed) do |topic, user|
    # Optional: Log or handle lottery deletion
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: topic.id)
    Rails.logger.info("Lottery deleted with topic #{topic.id}, state: #{lottery.state}") if lottery
  end

  # DEPRECATED: Custom fields registrations (replaced by normalized tables)
  # Register custom fields still used for Erhaltungsberichte (cross-plugin references)
  # packet_post_id: Post ID of the packet in the lottery (for Erhaltungsberichte)
  register_topic_custom_field_type("packet_post_id", :integer)
  # packet_topic_id: Topic ID of the lottery (for Erhaltungsberichte)
  register_topic_custom_field_type("packet_topic_id", :integer)

  # Add helper methods to Topic class to safely access lottery fields
  add_to_class(:topic, :lottery_state) { lottery&.state }

  add_to_class(:topic, :lottery_ends_at) { lottery&.ends_at }

  add_to_class(:topic, :lottery_draft?) { lottery&.draft? || false }

  add_to_class(:topic, :lottery_active?) { lottery&.active? || false }

  add_to_class(:topic, :lottery_finished?) { lottery&.finished? || false }

  add_to_class(:topic, :lottery_results) { lottery&.results }

  add_to_class(:topic, :lottery_drawn_at) { lottery&.drawn_at }

  add_to_class(:topic, :lottery_drawn?) { lottery&.drawn? || false }

  # Add lottery packet data to post serializer
  add_to_serializer(:post, :is_lottery_packet) do
    VzekcVerlosung::LotteryPacket.exists?(post_id: object.id)
  end

  add_to_serializer(:post, :is_lottery_intro) do
    # Intro is the first post in a lottery topic
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: object.topic_id)
    lottery.present? && object.post_number == 1
  end

  add_to_serializer(:post, :lottery_winner) do
    packet = VzekcVerlosung::LotteryPacket.find_by(post_id: object.id)
    packet&.winner&.username
  end

  # Include collection timestamp for lottery owner and winner
  add_to_serializer(
    :post,
    :packet_collected_at,
    include_condition: -> { VzekcVerlosung::LotteryPacket.exists?(post_id: object.id) },
  ) do
    packet = VzekcVerlosung::LotteryPacket.find_by(post_id: object.id)
    return nil unless packet

    # Show to lottery owner, staff, or winner
    topic = object.topic
    return nil unless topic

    is_winner = packet.winner_user_id.present? && scope.user&.id == packet.winner_user_id
    is_authorized = scope.is_staff? || topic.user_id == scope.user&.id || is_winner
    return nil unless is_authorized

    packet.collected_at
  end

  # Include erhaltungsbericht topic ID (only if topic still exists)
  add_to_serializer(
    :post,
    :erhaltungsbericht_topic_id,
    include_condition: -> { VzekcVerlosung::LotteryPacket.exists?(post_id: object.id) },
  ) do
    packet = VzekcVerlosung::LotteryPacket.find_by(post_id: object.id)
    return nil unless packet

    topic_id = packet.erhaltungsbericht_topic_id
    return nil unless topic_id

    # Check if the topic still exists
    Topic.exists?(id: topic_id) ? topic_id : nil
  end

  # Add lottery data to topic serializers
  add_to_serializer(:topic_view, :lottery_state) do
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: object.topic.id)
    lottery&.state
  end

  add_to_serializer(:topic_view, :lottery_ends_at) do
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: object.topic.id)
    lottery&.ends_at
  end

  add_to_serializer(:topic_view, :lottery_results) do
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: object.topic.id)
    lottery&.results
  end

  add_to_serializer(:topic_view, :lottery_drawn_at) do
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: object.topic.id)
    lottery&.drawn_at
  end

  # Preload lottery association for topic lists to prevent N+1 queries
  add_class_method(:topic_list, :preloaded_lottery_data) do
    @preloaded_lottery_data ||=
      VzekcVerlosung::Lottery.where(topic_id: topics.map(&:id)).index_by(&:topic_id)
  end

  add_to_serializer(:topic_list_item, :lottery_state) { object.lottery&.state }

  add_to_serializer(:topic_list_item, :lottery_ends_at) { object.lottery&.ends_at }

  add_to_serializer(:topic_list_item, :lottery_results) { object.lottery&.results }

  # Include packet reference fields for Erhaltungsberichte
  # These store which packet an Erhaltungsbericht is about
  add_to_serializer(:topic_view, :packet_post_id) do
    # Check if this topic IS an Erhaltungsbericht by looking for a packet that references it
    packet = VzekcVerlosung::LotteryPacket.find_by(erhaltungsbericht_topic_id: object.topic.id)
    packet&.post_id
  end

  add_to_serializer(:topic_view, :packet_topic_id) do
    # Check if this topic IS an Erhaltungsbericht by looking for a packet that references it
    packet = VzekcVerlosung::LotteryPacket.find_by(erhaltungsbericht_topic_id: object.topic.id)
    packet&.lottery&.topic_id
  end

  # Whitelist packet reference parameters for topic creation
  add_permitted_post_create_param(:packet_post_id)
  add_permitted_post_create_param(:packet_topic_id)

  # Register callback to establish bidirectional link when Erhaltungsbericht is created
  on(:topic_created) do |topic, opts, user|
    # Check if packet reference data is in opts (from composer)
    packet_post_id = opts[:packet_post_id]&.to_i
    packet_topic_id = opts[:packet_topic_id]&.to_i

    next if packet_post_id.blank? || packet_topic_id.blank?

    # Save packet reference to topic custom fields (for backward compatibility)
    topic.custom_fields["packet_post_id"] = packet_post_id
    topic.custom_fields["packet_topic_id"] = packet_topic_id
    topic.save_custom_fields

    # Find the lottery packet
    packet = VzekcVerlosung::LotteryPacket.find_by(post_id: packet_post_id)
    next unless packet

    # Verify the post belongs to the correct topic
    next unless packet.post.topic_id == packet_topic_id

    # Verify the user is the winner
    next unless packet.winner_user_id == user.id

    # Establish reverse link from packet to Erhaltungsbericht
    packet.link_report!(topic)
  end
end
