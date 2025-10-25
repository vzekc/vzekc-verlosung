# frozen_string_literal: true

module VzekcVerlosung
  # Service to create a lottery with main topic and packet topics
  #
  # @example
  #   VzekcVerlosung::CreateLottery.call(
  #     user: current_user,
  #     guardian: guardian,
  #     title: "Hardware Verlosung Januar 2025",
  #     description: "Beschreibung der Verlosung",
  #     category_id: 5,
  #     packets: [
  #       { title: "Packet 1", description: "Inhalt" },
  #       { title: "Packet 2", description: "Inhalt" }
  #     ]
  #   )
  #
  class CreateLottery
    include Service::Base

    params do
      attribute :title, :string
      attribute :description, :string
      attribute :category_id, :integer
      attribute :packets, :array

      validates :title, presence: true, length: { minimum: 3, maximum: 255 }
      validates :description, presence: true
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
      Rails.logger.info "Description: #{params.description}"
      Rails.logger.info "Category: #{category.id}"

      post_creator =
        PostCreator.new(
          user,
          title: params.title,
          raw: params.description,
          category: category.id,
          skip_validations: true,
        )

      post = post_creator.create

      Rails.logger.info "Post created: #{post.inspect}"
      Rails.logger.info "Post errors: #{post_creator.errors.full_messages}" if post_creator.errors.any?

      fail!("Failed to create main topic: #{post_creator.errors.full_messages.join(", ")}") unless post&.persisted?

      # Mark the intro post
      post.custom_fields["is_lottery_intro"] = true
      post.save_custom_fields

      context[:main_topic] = post.topic
    end

    def create_packet_posts(user:, params:)
      main_topic = context[:main_topic]

      params.packets.each_with_index do |packet_data, index|
        packet_title = packet_data[:title] || packet_data["title"] || "Packet #{index + 1}"
        packet_description = packet_data[:description] || packet_data["description"] || ""

        # Build the post content
        raw_content = "# #{packet_title}\n\n#{packet_description}"

        post_creator =
          PostCreator.new(
            user,
            raw: raw_content,
            topic_id: main_topic.id,
            skip_validations: true,
          )

        post = post_creator.create

        unless post&.persisted?
          fail!("Failed to create packet post: #{post_creator.errors.full_messages.join(", ")}")
        end

        # Mark this post as a lottery packet
        post.custom_fields["is_lottery_packet"] = true
        post.save_custom_fields
      end
    end

  end
end
