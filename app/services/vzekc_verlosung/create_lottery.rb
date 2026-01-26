# frozen_string_literal: true

module VzekcVerlosung
  # Service to create a lottery with main topic and packet topics
  #
  # @example
  #   VzekcVerlosung::CreateLottery.call(
  #     user: current_user,
  #     guardian: guardian,
  #     title: "Hardware Verlosung Januar 2025",
  #     duration_days: 14,
  #     category_id: 5,
  #     packets: [
  #       { title: "Packet 1" },
  #       { title: "Packet 2" }
  #     ]
  #   )
  #
  class CreateLottery
    include Service::Base

    params do
      attribute :title, :string
      attribute :raw, :string
      attribute :duration_days, :integer
      attribute :category_id, :integer
      attribute :packet_mode, :string
      attribute :single_packet_erhaltungsbericht_required, :boolean
      attribute :packets, :array
      attribute :has_abholerpaket, :boolean
      attribute :abholerpaket_title, :string
      attribute :abholerpaket_erhaltungsbericht_required, :boolean
      attribute :drawing_mode, :string
      attribute :donation_id, :integer

      validates :title, presence: true, length: { minimum: 3, maximum: 255 }
      validates :raw, presence: true, length: { minimum: 1 }
      validates :duration_days,
                presence: true,
                numericality: {
                  only_integer: true,
                  greater_than_or_equal_to: 7,
                  less_than_or_equal_to: 28,
                }
      validates :category_id, presence: true
      validates :packet_mode, inclusion: { in: %w[ein mehrere] }, allow_nil: true
      validates :drawing_mode, inclusion: { in: %w[automatic manual] }, allow_nil: true

      # Packets validation depends on packet_mode
      # For "ein" mode: packets can be empty
      # For "mehrere" mode: at least one packet required
      validates :packets,
                presence: true,
                length: {
                  minimum: 1,
                },
                if: -> { (packet_mode || "mehrere") == "mehrere" }
    end

    model :category
    policy :can_create_topics

    transaction do
      step :create_main_topic
      step :create_packet_posts
    end

    private

    def fetch_category(params:)
      Rails.logger.info "=== FETCH_CATEGORY ==="
      Rails.logger.info "Params class: #{params.class}"
      Rails.logger.info "Params: #{params.inspect}"
      Rails.logger.info "Category ID: #{params.category_id}"
      Category.find_by(id: params.category_id)
    end

    def can_create_topics(guardian:, category:)
      guardian.can_create_lottery?(category)
    end

    def create_main_topic(user:, params:, category:)
      Rails.logger.info "=== CREATE_MAIN_TOPIC ==="
      Rails.logger.info "User: #{user.id}"
      Rails.logger.info "Title: #{params.title}"
      Rails.logger.info "Category: #{category.id}"

      # Use provided raw content or fall back to template for backward compatibility
      description = params.raw.presence || SiteSetting.vzekc_verlosung_description_template

      post_creator =
        PostCreator.new(
          user,
          title: params.title,
          raw: description,
          category: category.id,
          skip_validations: true,
          skip_rate_limits: true,
        )

      post = post_creator.create

      Rails.logger.info "Post created: #{post.inspect}"
      if post_creator.errors.any?
        Rails.logger.info "Post errors: #{post_creator.errors.full_messages}"
      end

      unless post&.persisted?
        fail!("Failed to create main topic: #{post_creator.errors.full_messages.join(", ")}")
      end

      # Create lottery record for this topic in active state
      # Set ends_at based on duration_days from now
      ends_at = params.duration_days.days.from_now

      lottery =
        Lottery.create!(
          topic_id: post.topic_id,
          state: "active",
          duration_days: params.duration_days,
          drawing_mode: params.drawing_mode || "automatic",
          packet_mode: params.packet_mode || "mehrere",
          donation_id: params.donation_id,
          ends_at: ends_at,
        )

      context[:main_topic] = post.topic
      context[:lottery] = lottery
    end

    def create_packet_posts(user:, params:)
      main_topic = context[:main_topic]
      lottery = context[:lottery]

      # Get packet mode (default to "mehrere" for backward compatibility)
      packet_mode = params.packet_mode || "mehrere"

      if packet_mode == "ein"
        # Ein Paket mode: Create one LotteryPacket pointing to main post
        # No separate packet posts are created
        erhaltungsbericht_required =
          if params.single_packet_erhaltungsbericht_required.nil?
            true
          else
            params.single_packet_erhaltungsbericht_required
          end

        LotteryPacket.create!(
          lottery_id: lottery.id,
          post_id: main_topic.posts.first.id,
          ordinal: 1,
          title: params.title,
          quantity: 1, # Single packet mode always has quantity 1
          erhaltungsbericht_required: erhaltungsbericht_required,
          abholerpaket: false,
        )
      else
        # Mehrere Pakete mode: Create packet posts from packets array
        # The packets array now includes ordinals and is_abholerpaket flags from frontend

        # Determine if Abholerpaket should be created
        has_abholerpaket = params.has_abholerpaket.nil? ? true : params.has_abholerpaket
        abholerpaket_in_packets =
          params.packets.any? { |p| p[:is_abholerpaket] || p["is_abholerpaket"] }

        # If has_abholerpaket is true but not included in packets, create it
        if has_abholerpaket && !abholerpaket_in_packets
          abholerpaket_title = params.abholerpaket_title || "Abholerpaket"
          abholerpaket_erhaltungsbericht =
            (
              if params.abholerpaket_erhaltungsbericht_required.nil?
                true
              else
                params.abholerpaket_erhaltungsbericht_required
              end
            )

          # Create Abholerpaket post
          raw_content = "# Paket 0: #{abholerpaket_title}\n\nReserviert für den Abholer."
          post_creator =
            PostCreator.new(
              user,
              raw: raw_content,
              topic_id: main_topic.id,
              skip_validations: true,
              skip_rate_limits: true,
            )
          post = post_creator.create

          unless post&.persisted?
            fail!(
              "Failed to create Abholerpaket post: #{post_creator.errors.full_messages.join(", ")}",
            )
          end

          # Create Abholerpaket record (quantity always 1)
          abholerpaket_packet =
            LotteryPacket.create!(
              lottery_id: lottery.id,
              post_id: post.id,
              ordinal: 0,
              title: abholerpaket_title,
              quantity: 1,
              erhaltungsbericht_required: abholerpaket_erhaltungsbericht,
              abholerpaket: true,
            )

          # Create winner entry for Abholerpaket (pre-assigned to creator)
          # Set fulfillment_state based on whether Erhaltungsbericht is required
          abholerpaket_state =
            abholerpaket_packet.erhaltungsbericht_required ? "received" : "completed"
          LotteryPacketWinner.create!(
            lottery_packet_id: abholerpaket_packet.id,
            winner_user_id: user.id,
            instance_number: 1,
            won_at: Time.zone.now,
            collected_at: Time.zone.now,
            fulfillment_state: abholerpaket_state,
          )
        end

        # Start ordinal at 1 if Abholerpaket exists
        next_ordinal = has_abholerpaket ? 1 : 1

        # Track if we auto-created Abholerpaket above
        auto_created_abholerpaket = has_abholerpaket && !abholerpaket_in_packets

        params.packets.each_with_index do |packet_data, index|
          is_abholerpaket_packet = packet_data[:is_abholerpaket] || packet_data["is_abholerpaket"]
          # Skip if this is an Abholerpaket AND we already auto-created one above
          next if is_abholerpaket_packet && auto_created_abholerpaket
          packet_title = packet_data[:title] || packet_data["title"]
          packet_raw = packet_data[:raw] || packet_data["raw"] || ""
          # Auto-assign ordinal if not provided
          packet_ordinal = packet_data[:ordinal] || packet_data["ordinal"] || (next_ordinal + index)
          is_abholerpaket = packet_data[:is_abholerpaket] || packet_data["is_abholerpaket"] || false

          # Use nil check instead of key? to properly handle both string and symbol keys
          erb_value = packet_data[:erhaltungsbericht_required]
          erb_value = packet_data["erhaltungsbericht_required"] if erb_value.nil?
          erhaltungsbericht_required = erb_value.nil? ? true : erb_value

          # Build post with title heading and user content
          raw_content = "# Paket #{packet_ordinal}: #{packet_title}\n\n#{packet_raw}"

          post_creator =
            PostCreator.new(
              user,
              raw: raw_content,
              topic_id: main_topic.id,
              skip_validations: true,
              skip_rate_limits: true,
            )

          post = post_creator.create

          unless post&.persisted?
            fail!("Failed to create packet post: #{post_creator.errors.full_messages.join(", ")}")
          end

          # Get quantity (default 1, Abholerpaket always 1)
          packet_quantity = packet_data[:quantity] || packet_data["quantity"] || 1
          packet_quantity = 1 if is_abholerpaket # Abholerpaket always has quantity 1

          # Create lottery packet record
          lottery_packet =
            LotteryPacket.create!(
              lottery_id: lottery.id,
              post_id: post.id,
              ordinal: packet_ordinal,
              title: packet_title,
              quantity: packet_quantity,
              erhaltungsbericht_required: erhaltungsbericht_required,
              abholerpaket: is_abholerpaket,
            )

          # If this is Abholerpaket, assign to creator and mark collected
          if is_abholerpaket
            # Set fulfillment_state based on whether Erhaltungsbericht is required
            abholerpaket_winner_state =
              lottery_packet.erhaltungsbericht_required ? "received" : "completed"
            LotteryPacketWinner.create!(
              lottery_packet_id: lottery_packet.id,
              winner_user_id: user.id,
              instance_number: 1,
              won_at: Time.zone.now,
              collected_at: Time.zone.now,
              fulfillment_state: abholerpaket_winner_state,
            )
          end
        end
      end
    end
  end
end
