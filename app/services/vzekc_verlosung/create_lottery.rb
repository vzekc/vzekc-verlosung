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
      attribute :display_id, :integer
      attribute :duration_days, :integer
      attribute :category_id, :integer
      attribute :packets, :array
      attribute :has_abholerpaket, :boolean
      attribute :abholerpaket_title, :string

      validates :title, presence: true, length: { minimum: 3, maximum: 255 }
      validates :display_id, presence: true, numericality: { only_integer: true, greater_than: 400 }
      validates :duration_days,
                presence: true,
                numericality: {
                  only_integer: true,
                  greater_than_or_equal_to: 7,
                  less_than_or_equal_to: 28,
                }
      validates :category_id, presence: true
      validates :packets, presence: true, length: { minimum: 1 }
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
      guardian.can_create_topic_on_category?(category)
    end

    def create_main_topic(user:, params:, category:)
      Rails.logger.info "=== CREATE_MAIN_TOPIC ==="
      Rails.logger.info "User: #{user.id}"
      Rails.logger.info "Title: #{params.title}"
      Rails.logger.info "Category: #{category.id}"

      # Get the description template from site settings
      description = SiteSetting.vzekc_verlosung_description_template

      post_creator =
        PostCreator.new(
          user,
          title: params.title,
          raw: description,
          category: category.id,
          skip_validations: true,
        )

      post = post_creator.create

      Rails.logger.info "Post created: #{post.inspect}"
      if post_creator.errors.any?
        Rails.logger.info "Post errors: #{post_creator.errors.full_messages}"
      end

      unless post&.persisted?
        fail!("Failed to create main topic: #{post_creator.errors.full_messages.join(", ")}")
      end

      # Mark intro post
      post.custom_fields["is_lottery_intro"] = true
      post.save_custom_fields

      # Create lottery record for this topic
      lottery =
        Lottery.create!(
          topic_id: post.topic_id,
          display_id: params.display_id,
          state: "draft",
          duration_days: params.duration_days,
        )

      context[:main_topic] = post.topic
      context[:lottery] = lottery
    end

    def create_packet_posts(user:, params:)
      main_topic = context[:main_topic]
      lottery = context[:lottery]

      # Create Abholerpaket if requested (defaults to true if not specified)
      has_abholerpaket = params.has_abholerpaket.nil? ? true : params.has_abholerpaket

      if has_abholerpaket
        # Use provided title or default to "Abholerpaket"
        abholerpaket_title = params.abholerpaket_title.presence || "Abholerpaket"
        display_title = abholerpaket_title
        raw_content = "# #{display_title}\n\n"

        post_creator =
          PostCreator.new(user, raw: raw_content, topic_id: main_topic.id, skip_validations: true)

        post = post_creator.create

        unless post&.persisted?
          fail!(
            "Failed to create Abholerpaket post: #{post_creator.errors.full_messages.join(", ")}",
          )
        end

        # Create lottery packet record for Abholerpaket with ordinal 0
        # Assign winner to creator and mark as won and collected (since creator already has it)
        LotteryPacket.create!(
          lottery_id: lottery.id,
          post_id: post.id,
          ordinal: 0,
          title: abholerpaket_title,
          erhaltungsbericht_required: true,
          abholerpaket: true,
          winner_user_id: user.id,
          won_at: Time.zone.now,
          collected_at: Time.zone.now,
        )
      end

      # Create user-defined packets starting at ordinal 1
      params.packets.each_with_index do |packet_data, index|
        packet_ordinal = index + 1
        packet_title = packet_data[:title] || packet_data["title"]
        erhaltungsbericht_required =
          packet_data.key?(:erhaltungsbericht_required) ?
            packet_data[:erhaltungsbericht_required] :
            if packet_data.key?("erhaltungsbericht_required")
              packet_data["erhaltungsbericht_required"]
            else
              true
            end

        # Build the post title with prefix for display
        display_title =
          if packet_title.present?
            "Paket #{packet_ordinal}: #{packet_title}"
          else
            "Paket #{packet_ordinal}"
          end

        # Build the post content
        raw_content = "# #{display_title}\n\n"

        post_creator =
          PostCreator.new(user, raw: raw_content, topic_id: main_topic.id, skip_validations: true)

        post = post_creator.create

        unless post&.persisted?
          fail!("Failed to create packet post: #{post_creator.errors.full_messages.join(", ")}")
        end

        # Create lottery packet record with ordinal and user's title (no prefix)
        LotteryPacket.create!(
          lottery_id: lottery.id,
          post_id: post.id,
          ordinal: packet_ordinal,
          title: packet_title.presence || "Paket #{packet_ordinal}",
          erhaltungsbericht_required: erhaltungsbericht_required,
          abholerpaket: false,
        )
      end
    end
  end
end
