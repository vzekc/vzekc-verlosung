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
register_asset "stylesheets/donation-widget.scss"

register_svg_icon "trophy"
register_svg_icon "dice"
register_svg_icon "clock"
register_svg_icon "pen"
register_svg_icon "file"
register_svg_icon "file-alt"
register_svg_icon "gift"
register_svg_icon "hand-point-up"
register_svg_icon "user-plus"

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
  module GuardianExtensions
    def can_create_post?(topic)
      return false unless super
      can_create_post_in_lottery_draft?(topic)
    end
  end

  Guardian.prepend GuardianExtensions

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
  # donation_id: Donation ID (for Erhaltungsberichte created from donations)
  register_topic_custom_field_type("donation_id", :integer)

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

  add_to_serializer(:post, :is_abholerpaket) do
    packet = VzekcVerlosung::LotteryPacket.find_by(post_id: object.id)
    packet&.abholerpaket == true
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
  # Whitelist donation_id for Erhaltungsberichte from donations
  add_permitted_post_create_param(:donation_id)

  # Register callback to establish bidirectional link when Erhaltungsbericht is created
  on(:topic_created) do |topic, opts, user|
    # Handle Erhaltungsbericht from lottery packet
    packet_post_id = opts[:packet_post_id]&.to_i
    packet_topic_id = opts[:packet_topic_id]&.to_i

    if packet_post_id.present? && packet_topic_id.present?
      # Save packet reference to topic custom fields (for backward compatibility)
      topic.custom_fields["packet_post_id"] = packet_post_id
      topic.custom_fields["packet_topic_id"] = packet_topic_id
      topic.save_custom_fields

      # Find the lottery packet
      packet = VzekcVerlosung::LotteryPacket.find_by(post_id: packet_post_id)
      if packet
        # Verify the post belongs to the correct topic
        if packet.post.topic_id == packet_topic_id
          # Verify the user is the winner
          if packet.winner_user_id == user.id
            # Establish reverse link from packet to Erhaltungsbericht
            packet.link_report!(topic)
          end
        end
      end
    end

    # Handle Erhaltungsbericht from donation
    donation_id = opts[:donation_id]&.to_i

    if donation_id.present?
      # Save donation_id to topic custom fields
      topic.custom_fields["donation_id"] = donation_id
      topic.save_custom_fields

      Rails.logger.info("Linked Erhaltungsbericht topic #{topic.id} to donation #{donation_id}")
    end
  end

  # Sync erhaltungsbericht template to category whenever it changes
  on(:site_setting_changed) do |name, old_value, new_value|
    sync_template =
      lambda do |template|
        category_id = SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id
        next if category_id.blank?

        category = Category.find_by(id: category_id)
        next unless category

        category.update(topic_template: template)
        Rails.logger.info("Synced erhaltungsbericht template to category #{category_id}")
      end

    if name == :vzekc_verlosung_erhaltungsbericht_template
      sync_template.call(new_value)
    elsif name == :vzekc_verlosung_erhaltungsberichte_category_id
      # When category changes, sync current template to new category
      sync_template.call(SiteSetting.vzekc_verlosung_erhaltungsbericht_template)
    end
  end

  # Perform initial sync when plugin loads
  if SiteSetting.vzekc_verlosung_enabled
    category_id = SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id
    template = SiteSetting.vzekc_verlosung_erhaltungsbericht_template

    if category_id.present? && template.present?
      category = Category.find_by(id: category_id)
      if category
        category.update(topic_template: template)
        Rails.logger.info(
          "Synced erhaltungsbericht template to category #{category_id} on plugin load",
        )
      end
    end
  end

  # ========== DONATION SYSTEM ==========

  # Add associations to core Discourse models
  add_to_class(:topic, :donation) { @donation ||= VzekcVerlosung::Donation.find_by(topic_id: id) }

  # Add donation data to post serializer
  add_to_serializer(:post, :is_donation_post) do
    # Donation post is the first post in a donation topic
    return false unless object.post_number == 1
    VzekcVerlosung::Donation.exists?(topic_id: object.topic_id)
  end

  add_to_serializer(:post, :donation_data, include_condition: -> { object.post_number == 1 }) do
    donation = VzekcVerlosung::Donation.find_by(topic_id: object.topic_id)
    next unless donation

    {
      id: donation.id,
      state: donation.state,
      postcode: donation.postcode,
      creator_user_id: donation.creator_user_id,
      published_at: donation.published_at,
    }
  end

  # Add donation data to topic serializers
  add_to_serializer(:topic_view, :donation_state) do
    donation = VzekcVerlosung::Donation.find_by(topic_id: object.topic.id)
    donation&.state
  end

  add_to_serializer(:topic_view, :donation_data) do
    donation = VzekcVerlosung::Donation.find_by(topic_id: object.topic.id)
    return nil unless donation

    {
      id: donation.id,
      state: donation.state,
      postcode: donation.postcode,
      creator_user_id: donation.creator_user_id,
      published_at: donation.published_at,
    }
  end

  # Whitelist donation_id parameter for topic creation
  add_permitted_post_create_param(:donation_id)

  # Hook into topic creation to link donation_id from composer
  on(:topic_created) do |topic, opts, user|
    Rails.logger.info(
      "[VzekcVerlosung] topic_created hook fired: topic=#{topic.id}, user=#{user.username}, opts=#{opts.inspect}",
    )

    donation_id = opts[:donation_id]&.to_i
    if donation_id.blank?
      Rails.logger.info("[VzekcVerlosung] No donation_id found in opts")
      next
    end

    # Find the donation
    donation = VzekcVerlosung::Donation.find_by(id: donation_id)
    unless donation
      Rails.logger.warn("[VzekcVerlosung] Donation #{donation_id} not found")
      next
    end

    # Verify the user is the creator
    unless donation.creator_user_id == user.id
      Rails.logger.warn(
        "[VzekcVerlosung] User #{user.id} is not creator of donation #{donation_id}",
      )
      next
    end

    # Verify the donation is in draft state
    unless donation.draft?
      Rails.logger.warn("[VzekcVerlosung] Donation #{donation_id} is not in draft state")
      next
    end

    # Link the topic to the donation
    donation.update!(topic_id: topic.id)

    # Auto-publish the donation
    donation.publish!

    Rails.logger.info("Linked donation #{donation.id} to topic #{topic.id} and published")
  end

  # Filter draft donations from topic lists for non-owners
  TopicQuery.add_custom_filter(:donation_state) do |results, topic_query|
    user = topic_query.user

    # Filter out draft donations unless user is staff or owner
    results =
      results.where(
        "topics.id NOT IN (
        SELECT topic_id FROM vzekc_verlosung_donations
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
end
