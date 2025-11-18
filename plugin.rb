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
# file-lines is available in Discourse core by default (no registration needed)
register_svg_icon "gift"
register_svg_icon "hand-point-up"
register_svg_icon "hand-pointer"
register_svg_icon "user-plus"
register_svg_icon "ticket"
register_svg_icon "calendar-check"

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

  # Extend Guardian with custom permissions and override can_create_post
  Guardian.prepend VzekcVerlosung::GuardianExtensions

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

  # Add validation to Post model to prevent removing packet titles
  module PostValidationExtensions
    def self.prepended(base)
      base.validate :validate_packet_title_present
    end

    def validate_packet_title_present
      packet = VzekcVerlosung::LotteryPacket.find_by(post_id: id)
      return unless packet

      # Check if the post still has a valid packet title heading
      unless VzekcVerlosung::TitleExtractor.has_title?(raw)
        errors.add(
          :base,
          I18n.t("vzekc_verlosung.errors.packet_title_required", ordinal: packet.ordinal),
        )
        return
      end

      # Extract ordinal from post content
      post_ordinal = VzekcVerlosung::TitleExtractor.extract_packet_number(raw)
      if post_ordinal != packet.ordinal
        errors.add(
          :base,
          I18n.t(
            "vzekc_verlosung.errors.packet_ordinal_mismatch",
            expected: packet.ordinal,
            actual: post_ordinal,
          ),
        )
      end

      # Extract and validate title length
      title = VzekcVerlosung::TitleExtractor.extract_title(raw)
      if title.present?
        # Count non-whitespace characters
        non_whitespace_count = title.gsub(/\s/, "").length
        if non_whitespace_count < 3
          errors.add(:base, I18n.t("vzekc_verlosung.errors.packet_title_too_short", minimum: 3))
        end
      end
    end
  end

  Post.prepend PostValidationExtensions

  # Sync packet title from post content to database when edited
  on(:post_edited) do |post, topic_changed, user|
    packet = VzekcVerlosung::LotteryPacket.find_by(post_id: post.id)
    next unless packet

    # Extract new title from post markdown
    new_title = VzekcVerlosung::TitleExtractor.extract_title(post.raw)

    if new_title.present? && new_title != packet.title
      Rails.logger.info(
        "Syncing packet #{packet.ordinal} title: '#{packet.title}' → '#{new_title}'",
      )
      packet.update!(title: new_title)
    elsif new_title.blank?
      Rails.logger.warn(
        "Could not extract title from packet post #{post.id}, keeping database title: '#{packet.title}'",
      )
    end
  end

  on(:topic_destroyed) do |topic, user|
    # Log lottery deletion (foreign key cascade will delete the lottery)
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: topic.id)
    Rails.logger.info("Lottery deleted with topic #{topic.id}, state: #{lottery.state}") if lottery

    # Log donation topic deletion (foreign key cascade will delete the donation)
    donation = VzekcVerlosung::Donation.find_by(topic_id: topic.id)
    if donation
      Rails.logger.info(
        "Donation topic #{topic.id} deleted, cascading to donation #{donation.id}, state: #{donation.state}",
      )
    end

    # Log Erhaltungsbericht deletion (foreign key nullify will clear the link)
    # Check if this topic is an Erhaltungsbericht linked to a donation
    donation_with_eb = VzekcVerlosung::Donation.find_by(erhaltungsbericht_topic_id: topic.id)
    if donation_with_eb
      Rails.logger.info(
        "Erhaltungsbericht topic #{topic.id} deleted, unlinking from donation #{donation_with_eb.id}",
      )
    end

    # Check if this topic is an Erhaltungsbericht linked to a lottery packet
    packet_with_eb = VzekcVerlosung::LotteryPacket.find_by(erhaltungsbericht_topic_id: topic.id)
    if packet_with_eb
      Rails.logger.info(
        "Erhaltungsbericht topic #{topic.id} deleted, unlinking from packet #{packet_with_eb.id}",
      )
    end
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

  add_to_serializer(:post, :lottery_packet_ordinal) do
    packet = VzekcVerlosung::LotteryPacket.find_by(post_id: object.id)
    packet&.ordinal
  end

  add_to_serializer(:post, :erhaltungsbericht_required) do
    packet = VzekcVerlosung::LotteryPacket.find_by(post_id: object.id)
    packet&.erhaltungsbericht_required
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

  add_to_serializer(:topic_view, :lottery_drawing_mode) do
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: object.topic.id)
    lottery&.drawing_mode
  end

  # Add all lottery packets data to topic view to prevent AJAX requests
  # This eliminates the need for lottery-intro-summary to fetch packet data
  add_to_serializer(:topic_view, :lottery_packets) do
    lottery = VzekcVerlosung::Lottery.find_by(topic_id: object.topic.id)
    return [] unless lottery

    # Get lottery packets with eager loading
    lottery_packets =
      lottery
        .lottery_packets
        .includes(:post, :winner, :erhaltungsbericht_topic, lottery_tickets: :user)
        .order("posts.post_number")

    lottery_packets
      .map do |packet|
        # Skip packets where the post has been deleted
        next if packet.post.nil?

        # Get tickets and users for this packet
        tickets = packet.lottery_tickets
        ticket_count = tickets.count

        users =
          tickets.map do |ticket|
            {
              id: ticket.user.id,
              username: ticket.user.username,
              name: ticket.user.name,
              avatar_template: ticket.user.avatar_template,
            }
          end

        # Get winner user object if winner exists
        winner_obj = nil
        if packet.winner
          winner_obj = {
            id: packet.winner.id,
            username: packet.winner.username,
            name: packet.winner.name,
            avatar_template: packet.winner.avatar_template,
          }
        end

        packet_data = {
          post_id: packet.post_id,
          post_number: packet.post.post_number,
          title: packet.title,
          ticket_count: ticket_count,
          winner: winner_obj,
          users: users,
          ordinal: packet.ordinal,
          abholerpaket: packet.abholerpaket,
          erhaltungsbericht_required: packet.erhaltungsbericht_required,
        }

        # Include erhaltungsbericht_topic_id only if topic still exists
        if packet.erhaltungsbericht_topic_id && packet.erhaltungsbericht_topic
          packet_data[:erhaltungsbericht_topic_id] = packet.erhaltungsbericht_topic_id
        end

        # Only include collected_at for lottery owner, staff, or winner
        is_winner = packet.winner_user_id.present? && scope.user&.id == packet.winner_user_id
        is_authorized = scope.is_staff? || object.topic.user_id == scope.user&.id || is_winner
        packet_data[:collected_at] = packet.collected_at if is_authorized && packet.collected_at

        packet_data
      end
      .compact
  end

  # Add ticket status to packet posts to prevent AJAX requests
  # This eliminates the need for lottery-widget to fetch ticket data
  add_to_serializer(
    :post,
    :packet_ticket_status,
    include_condition: -> { VzekcVerlosung::LotteryPacket.exists?(post_id: object.id) },
  ) do
    packet = VzekcVerlosung::LotteryPacket.find_by(post_id: object.id)
    return nil unless packet

    # Get tickets with user data
    tickets = VzekcVerlosung::LotteryTicket.where(post_id: object.id).includes(:user)
    ticket_count = tickets.count

    users =
      tickets.map do |ticket|
        {
          id: ticket.user.id,
          username: ticket.user.username,
          name: ticket.user.name,
          avatar_template: ticket.user.avatar_template,
        }
      end

    # Get winner data
    winner = nil
    if packet.winner
      winner = {
        id: packet.winner.id,
        username: packet.winner.username,
        name: packet.winner.name,
        avatar_template: packet.winner.avatar_template,
      }
    end

    response = {
      has_ticket:
        scope.user &&
          VzekcVerlosung::LotteryTicket.exists?(post_id: object.id, user_id: scope.user.id),
      ticket_count: ticket_count,
      users: users,
      winner: winner,
    }

    # Include collected_at for lottery owner, staff, or winner
    topic = object.topic
    is_winner =
      packet.winner_user_id.present? && scope.user && scope.user.id == packet.winner_user_id
    is_authorized = scope.is_staff? || topic&.user_id == scope.user&.id || is_winner
    response[:collected_at] = packet.collected_at if is_authorized && packet.collected_at

    response
  end

  # Preload lottery association for topic lists to prevent N+1 queries
  add_class_method(:topic_list, :preloaded_lottery_data) do
    @preloaded_lottery_data ||=
      VzekcVerlosung::Lottery.where(topic_id: topics.map(&:id)).index_by(&:topic_id)
  end

  add_to_serializer(:topic_list_item, :lottery_state) { object.lottery&.state }

  add_to_serializer(:topic_list_item, :lottery_ends_at) { object.lottery&.ends_at }

  add_to_serializer(:topic_list_item, :lottery_results) { object.lottery&.results }

  add_to_serializer(:topic_list_item, :lottery_drawing_mode) { object.lottery&.drawing_mode }

  # Register custom field for Erhaltungsbericht donation source
  register_topic_custom_field_type("donation_id", :integer)

  # Add helper method to Topic class
  # Directly query the custom field to avoid strict preload enforcement
  add_to_class(:topic, :erhaltungsbericht_donation_id) do
    return @erhaltungsbericht_donation_id if defined?(@erhaltungsbericht_donation_id)
    @erhaltungsbericht_donation_id =
      TopicCustomField.where(topic_id: id, name: "donation_id").pick(:value)&.to_i
  end

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

  # Include donation source link for Erhaltungsberichte from donations
  # Returns complete link data to avoid additional HTTP requests in JavaScript
  # Add to both basic_topic (for lists) and topic_view (for full page)
  add_to_serializer(
    :basic_topic,
    :erhaltungsbericht_source_donation,
    include_condition: -> { object.erhaltungsbericht_donation_id.present? },
  ) do
    donation_id = object.erhaltungsbericht_donation_id
    return nil unless donation_id

    donation = VzekcVerlosung::Donation.find_by(id: donation_id)
    return nil unless donation&.topic

    { id: donation.topic.id, title: donation.topic.title, url: donation.topic.url }
  end

  add_to_serializer(
    :topic_view,
    :erhaltungsbericht_source_donation,
    include_condition: -> { object.topic.erhaltungsbericht_donation_id.present? },
  ) do
    donation_id = object.topic.erhaltungsbericht_donation_id
    return nil unless donation_id

    donation = VzekcVerlosung::Donation.find_by(id: donation_id)
    return nil unless donation&.topic

    { id: donation.topic.id, title: donation.topic.title, url: donation.topic.url }
  end

  # Include lottery packet source link for Erhaltungsberichte from lottery packets
  # Returns complete link data to avoid additional HTTP requests in JavaScript
  # Add to both basic_topic (for lists) and topic_view (for full page)
  add_to_serializer(
    :basic_topic,
    :erhaltungsbericht_source_packet,
    include_condition: -> do
      VzekcVerlosung::LotteryPacket.exists?(erhaltungsbericht_topic_id: object.id)
    end,
  ) do
    packet = VzekcVerlosung::LotteryPacket.find_by(erhaltungsbericht_topic_id: object.id)
    return nil unless packet&.lottery&.topic

    {
      lottery_title: packet.lottery.topic.title,
      packet_url: "/t/#{packet.lottery.topic.slug}/#{packet.lottery.topic.id}/#{packet.post_id}",
    }
  end

  add_to_serializer(
    :topic_view,
    :erhaltungsbericht_source_packet,
    include_condition: -> do
      VzekcVerlosung::LotteryPacket.exists?(erhaltungsbericht_topic_id: object.topic.id)
    end,
  ) do
    packet = VzekcVerlosung::LotteryPacket.find_by(erhaltungsbericht_topic_id: object.topic.id)
    return nil unless packet&.lottery&.topic

    {
      lottery_title: packet.lottery.topic.title,
      packet_url: "/t/#{packet.lottery.topic.slug}/#{packet.lottery.topic.id}/#{packet.post_id}",
    }
  end

  # Legacy fields for backward compatibility (kept for existing code)
  add_to_serializer(:basic_topic, :erhaltungsbericht_donation_id) do
    object.erhaltungsbericht_donation_id
  end

  add_to_serializer(:basic_topic, :packet_post_id) do
    packet = VzekcVerlosung::LotteryPacket.find_by(erhaltungsbericht_topic_id: object.id)
    packet&.post_id
  end

  add_to_serializer(:basic_topic, :packet_topic_id) do
    packet = VzekcVerlosung::LotteryPacket.find_by(erhaltungsbericht_topic_id: object.id)
    packet&.lottery&.topic_id
  end

  # Whitelist packet reference parameters for topic creation
  add_permitted_post_create_param(:packet_post_id)
  add_permitted_post_create_param(:packet_topic_id)
  # Whitelist erhaltungsbericht_donation_id for Erhaltungsberichte from donations
  add_permitted_post_create_param(:erhaltungsbericht_donation_id)

  # Register callback to establish bidirectional link when Erhaltungsbericht is created
  on(:topic_created) do |topic, opts, user|
    # Handle Erhaltungsbericht from lottery packet (all packets including Abholerpaket)
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
    # Read from erhaltungsbericht_donation_id parameter (sent by erhaltungsbericht-composer.js)
    erhaltungsbericht_donation_id = opts[:erhaltungsbericht_donation_id]&.to_i

    if erhaltungsbericht_donation_id.present?
      # CRITICAL: Check if this is actually an Erhaltungsbericht topic,
      # not a donation topic. Both pass donation_id, so we distinguish by category.
      erhaltungsberichte_category_id =
        SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id.to_i

      if erhaltungsberichte_category_id.present? &&
           topic.category_id == erhaltungsberichte_category_id
        # This is an Erhaltungsbericht topic - link it to the donation
        # Save donation_id to topic custom fields for UI lookups
        topic.custom_fields["donation_id"] = erhaltungsbericht_donation_id
        topic.save_custom_fields

        # Set business state: Link Erhaltungsbericht topic to donation
        donation = VzekcVerlosung::Donation.find_by(id: erhaltungsbericht_donation_id)
        if donation
          donation.update!(erhaltungsbericht_topic_id: topic.id)
          Rails.logger.info("Linked Erhaltungsbericht topic #{topic.id} to donation #{donation.id}")
        else
          Rails.logger.warn(
            "Could not find donation #{erhaltungsbericht_donation_id} for Erhaltungsbericht topic #{topic.id}",
          )
        end
      else
        # This is a donation topic - donation_id is just for reference, don't set erhaltungsbericht_topic_id
        Rails.logger.debug(
          "Topic #{topic.id} has donation_id #{erhaltungsbericht_donation_id} but is not in Erhaltungsberichte category - skipping erhaltungsbericht link",
        )
      end
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

    lottery_topic = donation.lottery&.topic
    lottery_data =
      if lottery_topic
        { id: donation.lottery.id, topic_id: lottery_topic.id, url: lottery_topic.url }
      end

    {
      id: donation.id,
      state: donation.state,
      postcode: donation.postcode,
      creator_user_id: donation.creator_user_id,
      published_at: donation.published_at,
      lottery_id: donation.lottery&.id,
      lottery: lottery_data,
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

    lottery_topic = donation.lottery&.topic
    lottery_data =
      if lottery_topic
        { id: donation.lottery.id, topic_id: lottery_topic.id, url: lottery_topic.url }
      end

    {
      id: donation.id,
      state: donation.state,
      postcode: donation.postcode,
      creator_user_id: donation.creator_user_id,
      published_at: donation.published_at,
      lottery_id: donation.lottery&.id,
      lottery: lottery_data,
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
