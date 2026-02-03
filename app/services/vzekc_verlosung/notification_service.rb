# frozen_string_literal: true

module VzekcVerlosung
  # Unified notification service that handles all notification sending AND logging automatically.
  # This ensures logging cannot be skipped when adding new notifications.
  #
  # Usage:
  #   NotificationService.notify(:lottery_won, recipient: user, context: { lottery: lottery })
  #   NotificationService.notify_batch(:lottery_drawn, recipients: users, context: { lottery: lottery })
  #
  class NotificationService
    # All notification types defined in one place
    NOTIFICATION_TYPES = {
      # In-app notifications (5)
      ticket_bought: {
        delivery: :in_app,
        discourse_type: :vzekc_verlosung_ticket_bought,
      },
      ticket_returned: {
        delivery: :in_app,
        discourse_type: :vzekc_verlosung_ticket_returned,
      },
      lottery_drawn: {
        delivery: :in_app,
        discourse_type: :vzekc_verlosung_drawn,
      },
      lottery_won: {
        delivery: :in_app,
        discourse_type: :vzekc_verlosung_won,
      },
      did_not_win: {
        delivery: :in_app,
        discourse_type: :vzekc_verlosung_did_not_win,
      },
      # PM notifications (12)
      winner_pm: {
        delivery: :pm,
        template: "winner_message",
      },
      packet_shipped: {
        delivery: :pm,
        template: "notifications.packet_shipped",
      },
      donation_assigned: {
        delivery: :pm,
        template: "notifications.donation_assigned",
      },
      draft_reminder: {
        delivery: :pm,
        template: "reminders.draft",
      },
      donation_reminder: {
        delivery: :pm,
        template: "reminders.donation",
      },
      ending_tomorrow_reminder: {
        delivery: :pm,
        template: "reminders.ending_tomorrow",
      },
      ended_reminder: {
        delivery: :pm,
        template: "reminders.ended",
      },
      no_participants_reminder: {
        delivery: :pm,
        template: "reminders.no_participants",
      },
      donation_picked_up_reminder: {
        delivery: :pm,
        template: "reminders.donation_picked_up",
      },
      erhaltungsbericht_reminder: {
        delivery: :pm,
        template: "reminders.erhaltungsbericht",
      },
      uncollected_reminder: {
        delivery: :pm,
        template: "reminders.uncollected",
      },
      merch_packet_ready: {
        delivery: :pm,
        template: "notifications.merch_packet_ready",
      },
    }.freeze

    class << self
      # Send a single notification
      #
      # @param type [Symbol] Notification type from NOTIFICATION_TYPES
      # @param recipient [User] User to notify
      # @param context [Hash] Context data for building notification
      # @return [NotificationLog] The created log entry
      def notify(type, recipient:, context: {})
        new(type, recipient: recipient, context: context).deliver
      end

      # Send notifications to multiple recipients
      #
      # @param type [Symbol] Notification type from NOTIFICATION_TYPES
      # @param recipients [Array<User>] Users to notify
      # @param context [Hash] Context data for building notification
      # @return [Array<NotificationLog>] The created log entries
      def notify_batch(type, recipients:, context: {})
        recipients.filter_map { |recipient| notify(type, recipient: recipient, context: context) }
      end

      # Notify merch handlers that a merch packet is ready
      #
      # @param donation [Donation] The donation with a merch packet
      def notify_merch_handlers(donation:)
        group_name = SiteSetting.vzekc_verlosung_merch_handlers_group_name
        return if group_name.blank?

        group = Group.find_by(name: group_name)
        return unless group

        group.users.each do |user|
          notify(:merch_packet_ready, recipient: user, context: { donation: donation })
        end
      end

      # Send email to donor when merch packet is shipped
      #
      # @param email [String] Donor's email address
      # @param donor_name [String] Donor's name
      # @param tracking_info [String] Optional tracking information
      # @param donation [Donation] The associated donation
      def send_merch_packet_shipped_email(email:, donor_name:, tracking_info:, donation:)
        return if email.blank?

        subject =
          I18n.t("vzekc_verlosung.notifications.merch_packet_shipped.subject")

        body =
          if tracking_info.present?
            I18n.t(
              "vzekc_verlosung.notifications.merch_packet_shipped.body_with_tracking",
              donor_name: donor_name,
              tracking_info: tracking_info,
            )
          else
            I18n.t(
              "vzekc_verlosung.notifications.merch_packet_shipped.body",
              donor_name: donor_name,
            )
          end

        Email::Sender.new(
          build_merch_packet_email(email, subject, body),
          :vzekc_verlosung_merch_packet_shipped,
        ).send
      rescue => e
        Rails.logger.error("Failed to send merch packet shipped email: #{e.message}")
      end

      private

      def build_merch_packet_email(to_address, subject, body)
        message = Mail::Message.new
        message.to = to_address
        message.from = SiteSetting.notification_email
        message.subject = subject
        message.body = body
        message
      end
    end

    def initialize(type, recipient:, context: {})
      @type = type
      @recipient = recipient
      @context = context
      @config = NOTIFICATION_TYPES[type]

      raise ArgumentError, "Unknown notification type: #{type}" unless @config
    end

    def deliver
      return nil unless should_deliver?

      result = nil
      error_message = nil

      begin
        result =
          if @config[:delivery] == :in_app
            deliver_in_app
          else
            deliver_pm
          end

        # If result is nil, the notification data couldn't be built
        error_message = "Notification data could not be built" if result.nil?
      rescue => e
        error_message = "#{e.class}: #{e.message}"
        Rails.logger.error(
          "NotificationService error delivering #{@type} to user #{@recipient.id}: #{error_message}",
        )
      end

      log_notification(success: error_message.nil?, error_message: error_message)
    end

    private

    def should_deliver?
      return false unless @recipient
      return false unless MemberChecker.active_member?(@recipient)

      # Check packet-level notification silence for uncollected reminders
      if @type == :uncollected_reminder
        packet = @context[:packet]
        return false if packet&.notifications_silenced?
      end

      true
    end

    def deliver_in_app
      notification_data = build_in_app_data
      return nil unless notification_data

      Notification.consolidate_or_create!(
        notification_type: Notification.types[@config[:discourse_type]],
        user_id: @recipient.id,
        topic_id: notification_data[:topic_id],
        post_number: notification_data[:post_number] || 1,
        data: notification_data[:data].to_json,
      )
    end

    def deliver_pm
      pm_data = build_pm_data
      return nil unless pm_data

      # Reload sender to avoid stale class references in development mode
      sender = pm_data[:sender]
      sender = User.find(sender.id) if sender.is_a?(User)

      PostCreator.create!(
        sender,
        title: pm_data[:title],
        raw: pm_data[:body],
        archetype: Archetype.private_message,
        subtype: pm_data[:subtype] || TopicSubtype.system_message,
        target_usernames: @recipient.username,
        skip_validations: true,
      )
    end

    def build_in_app_data
      case @type
      when :ticket_bought
        build_ticket_bought_data
      when :ticket_returned
        build_ticket_returned_data
      when :lottery_drawn
        build_lottery_drawn_data
      when :lottery_won
        build_lottery_won_data
      when :did_not_win
        build_did_not_win_data
      end
    end

    def build_pm_data
      case @type
      when :winner_pm
        build_winner_pm_data
      when :packet_shipped
        build_packet_shipped_pm_data
      when :donation_assigned
        build_donation_assigned_pm_data
      when :draft_reminder
        build_draft_reminder_pm_data
      when :donation_reminder
        build_donation_reminder_pm_data
      when :ending_tomorrow_reminder
        build_ending_tomorrow_reminder_pm_data
      when :ended_reminder
        build_ended_reminder_pm_data
      when :no_participants_reminder
        build_no_participants_reminder_pm_data
      when :donation_picked_up_reminder
        build_donation_picked_up_reminder_pm_data
      when :erhaltungsbericht_reminder
        build_erhaltungsbericht_reminder_pm_data
      when :uncollected_reminder
        build_uncollected_reminder_pm_data
      when :merch_packet_ready
        build_merch_packet_ready_pm_data
      end
    end

    # In-app notification data builders

    def build_ticket_bought_data
      topic = @context[:topic]
      post = @context[:post]
      buyer = @context[:buyer]

      return nil unless topic && post && buyer

      packet_title = TitleExtractor.extract_title(post.raw) || "Packet ##{post.post_number}"

      {
        topic_id: topic.id,
        post_number: post.post_number,
        data: {
          display_username: buyer.username,
          packet_title: packet_title,
        },
      }
    end

    def build_ticket_returned_data
      topic = @context[:topic]
      post = @context[:post]
      returner = @context[:returner]

      return nil unless topic && post && returner

      packet_title = TitleExtractor.extract_title(post.raw) || "Packet ##{post.post_number}"

      {
        topic_id: topic.id,
        post_number: post.post_number,
        data: {
          display_username: returner.username,
          packet_title: packet_title,
        },
      }
    end

    def build_lottery_drawn_data
      topic = @context[:topic]

      return nil unless topic

      {
        topic_id: topic.id,
        post_number: 1,
        data: {
          topic_title: topic.title,
          message: "vzekc_verlosung.notifications.lottery_drawn",
        },
      }
    end

    def build_lottery_won_data
      topic = @context[:topic]
      packet = @context[:packet]
      instance_number = @context[:instance_number] || 1
      total_instances = @context[:total_instances] || 1

      return nil unless topic && packet

      {
        topic_id: topic.id,
        post_number: packet.post&.post_number || 1,
        data: {
          packet_title: packet.title,
          instance_number: instance_number,
          total_instances: total_instances,
          message: "vzekc_verlosung.notifications.lottery_won",
        },
      }
    end

    def build_did_not_win_data
      topic = @context[:topic]

      return nil unless topic

      {
        topic_id: topic.id,
        post_number: 1,
        data: {
          topic_title: topic.title,
          message: "vzekc_verlosung.notifications.did_not_win",
        },
      }
    end

    # PM data builders

    def build_winner_pm_data
      topic = @context[:topic]
      packets = @context[:packets]

      return nil unless topic && packets&.any?

      sender = topic.user

      # Get the main post content (excluding images)
      main_post = topic.posts.first
      main_post_content = strip_images_from_markdown(main_post.raw)

      # Build packet list with links
      packet_list =
        packets
          .map do |packet|
            packet_url = "#{Discourse.base_url}#{topic.relative_url}/#{packet[:post_number]}"
            "- [#{packet[:title]}](#{packet_url})"
          end
          .join("\n")

      {
        sender: sender,
        title:
          I18n.t(
            "vzekc_verlosung.winner_message.title",
            locale: @recipient.effective_locale,
            topic_title: topic.title,
          ),
        body:
          I18n.t(
            "vzekc_verlosung.winner_message.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            topic_title: topic.title,
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
            packet_list: packet_list,
            main_post_content: main_post_content,
          ),
        subtype: nil, # Not a system message, from lottery owner
      }
    end

    def build_packet_shipped_pm_data
      packet = @context[:packet]
      lottery_topic = @context[:lottery_topic]
      sender = @context[:sender]
      tracking_info = @context[:tracking_info]

      return nil unless packet && lottery_topic && sender

      packet_title = packet.title || "Paket ##{packet.ordinal}"

      body_key =
        (
          if tracking_info.present?
            "notifications.packet_shipped.body_with_tracking"
          else
            "notifications.packet_shipped.body"
          end
        )

      body_params = {
        locale: @recipient.effective_locale,
        username: @recipient.username,
        sender_username: sender.username,
        packet_title: packet_title,
        lottery_title: lottery_topic.title,
        lottery_url: "#{Discourse.base_url}#{lottery_topic.relative_url}",
      }
      body_params[:tracking_info] = tracking_info if tracking_info.present?

      {
        sender: sender,
        title:
          I18n.t(
            "vzekc_verlosung.notifications.packet_shipped.title",
            locale: @recipient.effective_locale,
            packet_title: packet_title,
          ),
        body: I18n.t("vzekc_verlosung.#{body_key}", **body_params),
        subtype: nil, # Not a system message, from lottery owner
      }
    end

    def build_donation_assigned_pm_data
      donation = @context[:donation]
      contact_info = @context[:contact_info]

      return nil unless donation&.topic && contact_info

      {
        sender: donation.facilitator,
        title:
          I18n.t(
            "vzekc_verlosung.notifications.donation_assigned.title",
            locale: @recipient.effective_locale,
            topic_title: donation.topic.title,
          ),
        body:
          I18n.t(
            "vzekc_verlosung.notifications.donation_assigned.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            topic_title: donation.topic.title,
            topic_url: "#{Discourse.base_url}#{donation.topic.relative_url}",
            contact_info: contact_info,
          ),
        subtype: nil, # Not a system message, from facilitator
      }
    end

    def build_draft_reminder_pm_data
      lottery = @context[:lottery]
      topic = lottery&.topic

      return nil unless topic

      {
        sender: Discourse.system_user,
        title: I18n.t("vzekc_verlosung.reminders.draft.title", locale: @recipient.effective_locale),
        body:
          I18n.t(
            "vzekc_verlosung.reminders.draft.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            topic_title: topic.title,
            created_at: topic.created_at.strftime("%d.%m.%Y"),
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
          ),
        subtype: TopicSubtype.system_message,
      }
    end

    def build_donation_reminder_pm_data
      donation = @context[:donation]
      topic = donation&.topic

      return nil unless topic

      {
        sender: Discourse.system_user,
        title:
          I18n.t("vzekc_verlosung.reminders.donation.title", locale: @recipient.effective_locale),
        body:
          I18n.t(
            "vzekc_verlosung.reminders.donation.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            topic_title: topic.title,
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
          ),
        subtype: TopicSubtype.system_message,
      }
    end

    def build_ending_tomorrow_reminder_pm_data
      lottery = @context[:lottery]
      topic = lottery&.topic

      return nil unless topic && lottery&.ends_at

      {
        sender: Discourse.system_user,
        title:
          I18n.t(
            "vzekc_verlosung.reminders.ending_tomorrow.title",
            locale: @recipient.effective_locale,
          ),
        body:
          I18n.t(
            "vzekc_verlosung.reminders.ending_tomorrow.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            topic_title: topic.title,
            ending_at: lottery.ends_at.strftime("%d.%m.%Y"),
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
          ),
        subtype: TopicSubtype.system_message,
      }
    end

    def build_ended_reminder_pm_data
      lottery = @context[:lottery]
      topic = lottery&.topic

      return nil unless topic && lottery&.ends_at

      {
        sender: Discourse.system_user,
        title: I18n.t("vzekc_verlosung.reminders.ended.title", locale: @recipient.effective_locale),
        body:
          I18n.t(
            "vzekc_verlosung.reminders.ended.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            topic_title: topic.title,
            ended_at: lottery.ends_at.strftime("%d.%m.%Y"),
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
          ),
        subtype: TopicSubtype.system_message,
      }
    end

    def build_no_participants_reminder_pm_data
      lottery = @context[:lottery]
      topic = lottery&.topic

      return nil unless topic && lottery&.ends_at

      {
        sender: Discourse.system_user,
        title:
          I18n.t(
            "vzekc_verlosung.reminders.no_participants.title",
            locale: @recipient.effective_locale,
          ),
        body:
          I18n.t(
            "vzekc_verlosung.reminders.no_participants.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            topic_title: topic.title,
            ended_at: lottery.ends_at.strftime("%d.%m.%Y"),
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
          ),
        subtype: TopicSubtype.system_message,
      }
    end

    def build_donation_picked_up_reminder_pm_data
      donation = @context[:donation]
      topic = donation&.topic

      return nil unless topic

      {
        sender: Discourse.system_user,
        title:
          I18n.t(
            "vzekc_verlosung.reminders.donation_picked_up.title",
            locale: @recipient.effective_locale,
            topic_title: topic.title,
          ),
        body:
          I18n.t(
            "vzekc_verlosung.reminders.donation_picked_up.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            topic_title: topic.title,
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
          ),
        subtype: TopicSubtype.system_message,
      }
    end

    def build_erhaltungsbericht_reminder_pm_data
      lottery_topic = @context[:lottery_topic]
      packet_post = @context[:packet_post]
      packet_title = @context[:packet_title]
      days_since_collected = @context[:days_since_collected]

      return nil unless lottery_topic && packet_post && packet_title

      packet_url =
        "#{Discourse.base_url}/t/#{lottery_topic.slug}/#{lottery_topic.id}/#{packet_post.post_number}"

      {
        sender: Discourse.system_user,
        title:
          I18n.t(
            "vzekc_verlosung.reminders.erhaltungsbericht.title",
            locale: @recipient.effective_locale,
            packet_title: packet_title,
          ),
        body:
          I18n.t(
            "vzekc_verlosung.reminders.erhaltungsbericht.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            lottery_title: lottery_topic.title,
            packet_title: packet_title,
            days_since_collected: days_since_collected,
            packet_url: packet_url,
          ),
        subtype: TopicSubtype.system_message,
      }
    end

    def build_uncollected_reminder_pm_data
      lottery_topic = @context[:lottery_topic]
      uncollected_packets = @context[:uncollected_packets]
      days_since_drawn = @context[:days_since_drawn]

      return nil unless lottery_topic && uncollected_packets&.any?

      packet_list =
        uncollected_packets.map { |p| "- #{p[:title]} (Winner: #{p[:winner]})" }.join("\n")

      {
        sender: Discourse.system_user,
        title:
          I18n.t(
            "vzekc_verlosung.reminders.uncollected.title",
            locale: @recipient.effective_locale,
            uncollected_count: uncollected_packets.count,
          ),
        body:
          I18n.t(
            "vzekc_verlosung.reminders.uncollected.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            topic_title: lottery_topic.title,
            days_since_drawn: days_since_drawn,
            packet_list: packet_list,
            topic_url: "#{Discourse.base_url}#{lottery_topic.relative_url}",
          ),
        subtype: TopicSubtype.system_message,
      }
    end

    def build_merch_packet_ready_pm_data
      donation = @context[:donation]
      topic = donation&.topic
      merch_packet = donation&.merch_packet

      return nil unless topic && merch_packet

      {
        sender: Discourse.system_user,
        title:
          I18n.t(
            "vzekc_verlosung.notifications.merch_packet_ready.title",
            locale: @recipient.effective_locale,
            topic_title: topic.title,
          ),
        body:
          I18n.t(
            "vzekc_verlosung.notifications.merch_packet_ready.body",
            locale: @recipient.effective_locale,
            username: @recipient.username,
            topic_title: topic.title,
            topic_url: "#{Discourse.base_url}#{topic.relative_url}",
            merch_packets_url: "#{Discourse.base_url}/vzekc-verlosung/merch-packets?ship=#{merch_packet.id}",
          ),
        subtype: TopicSubtype.system_message,
      }
    end

    def log_notification(success:, error_message: nil)
      NotificationLog.create!(
        recipient_user_id: @recipient.id,
        notification_type: @type.to_s,
        delivery_method: @config[:delivery].to_s,
        lottery_id: extract_lottery_id,
        donation_id: extract_donation_id,
        lottery_packet_id: extract_packet_id,
        topic_id: extract_topic_id,
        post_id: extract_post_id,
        actor_user_id: extract_actor_id,
        payload: @context.transform_values { |v| serialize_for_payload(v) },
        success: success,
        error_message: error_message,
      )
    end

    def extract_lottery_id
      return @context[:lottery]&.id if @context[:lottery]
      return @context[:packet]&.lottery_id if @context[:packet]

      # For notifications with lottery_topic context, look up the lottery
      Lottery.find_by(topic_id: @context[:lottery_topic].id)&.id if @context[:lottery_topic]
    end

    def extract_donation_id
      @context[:donation]&.id
    end

    def extract_packet_id
      @context[:packet]&.id
    end

    def extract_topic_id
      @context[:topic]&.id || @context[:lottery_topic]&.id || @context[:lottery]&.topic_id ||
        @context[:donation]&.topic_id
    end

    def extract_post_id
      @context[:post]&.id || @context[:packet_post]&.id || @context[:packet]&.post_id
    end

    def extract_actor_id
      @context[:buyer]&.id || @context[:returner]&.id || @context[:sender]&.id
    end

    def serialize_for_payload(value)
      case value
      when ActiveRecord::Base
        { class: value.class.name, id: value.id }
      when Array
        value.map { |v| serialize_for_payload(v) }
      when Hash
        value.transform_values { |v| serialize_for_payload(v) }
      else
        value
      end
    end

    def strip_images_from_markdown(content)
      # Remove markdown images: ![alt](url)
      content = content.gsub(/!\[.*?\]\(.*?\)/, "")

      # Remove HTML img tags
      content = content.gsub(/<img[^>]*>/, "")

      # Remove standalone image URLs that might be on their own line
      content = content.gsub(%r{^\s*https?://\S+\.(jpg|jpeg|png|gif|webp)\s*$}i, "")

      content.strip
    end
  end
end
