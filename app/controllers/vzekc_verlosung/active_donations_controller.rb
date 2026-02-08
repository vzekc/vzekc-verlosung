# frozen_string_literal: true

module VzekcVerlosung
  class ActiveDonationsController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    # GET /vzekc-verlosung/active-donations.json
    #
    # Returns a list of all donations (excluding drafts) ordered by published date
    #
    # @return [JSON] {
    #   donations: [Array of donation objects]
    # }
    def index
      donations =
        Donation
          .joins(:topic)
          .where.not(state: "draft")
          .includes(:pickup_offers, topic: [:category, { user: :primary_group }])
          .order(published_at: :desc)

      read_topic_ids = read_topic_ids_for(donations)

      render json: {
               donations:
                 donations.map { |donation| build_donation_response(donation, read_topic_ids) },
             }
    end

    private

    # Build donation response data
    #
    # @param donation [Donation] The donation
    # @return [Hash] Donation data
    # Get topic IDs the current user has read
    #
    # @param donations [ActiveRecord::Relation] Donations to check
    # @return [Set<Integer>] Set of topic IDs the user has read
    def read_topic_ids_for(donations)
      return Set.new unless current_user

      topic_ids = donations.map(&:topic_id).compact
      return Set.new if topic_ids.empty?

      TopicUser
        .where(user_id: current_user.id, topic_id: topic_ids)
        .where.not(first_visited_at: nil)
        .pluck(:topic_id)
        .to_set
    end

    def build_donation_response(donation, read_topic_ids)
      topic = donation.topic

      # Count pickup offers
      pickup_offer_count = donation.pickup_offers.count

      # Find the assigned picker if any
      assigned_offer = donation.pickup_offers.find_by(state: %w[assigned picked_up])
      assigned_picker =
        if assigned_offer
          user = assigned_offer.user
          {
            id: user&.id,
            username: user&.username,
            name: user&.name,
            avatar_template: user&.avatar_template,
          }
        end

      # Only mark as unread if the topic is recent (< 4 weeks) and user hasn't read it
      is_unread =
        current_user && topic.created_at > 4.weeks.ago && !read_topic_ids.include?(topic.id)

      {
        id: donation.id,
        topic_id: topic.id,
        title: topic.title,
        url: topic.relative_url,
        state: donation.state,
        postcode: donation.postcode,
        published_at: donation.published_at,
        created_at: topic.created_at,
        unread: is_unread,
        pickup_offer_count: pickup_offer_count,
        assigned_picker: assigned_picker,
        has_lottery: donation.lottery.present?,
        has_erhaltungsbericht: donation.erhaltungsbericht_topic_id.present?,
        category: {
          id: topic.category&.id,
          name: topic.category&.name,
          slug: topic.category&.slug,
          color: topic.category&.color,
        },
        facilitator: {
          id: topic.user&.id,
          username: topic.user&.username,
          name: topic.user&.name,
          avatar_template: topic.user&.avatar_template,
          admin: topic.user&.admin,
          moderator: topic.user&.moderator,
          title: topic.user&.title,
          primary_group_name: topic.user&.primary_group&.name,
        },
      }
    end
  end
end
