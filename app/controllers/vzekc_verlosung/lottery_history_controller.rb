# frozen_string_literal: true

module VzekcVerlosung
  class LotteryHistoryController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME
    requires_login

    # GET /vzekc-verlosung/history.json
    #
    # Returns a flat list of all packets from finished lotteries
    #
    # Query parameters:
    # - search: Filter by lottery or packet title (case-insensitive)
    # - sort: Sort order (date_desc, date_asc, lottery_asc, lottery_desc)
    #
    # @return [JSON] {
    #   packets: [Array of packet objects with lottery info and winners]
    # }
    def index
      search = params[:search]
      sort = params[:sort] || "date_desc"

      # Get all finished lotteries
      lotteries =
        Topic
          .joins("INNER JOIN topic_custom_fields tcf ON tcf.topic_id = topics.id")
          .where("tcf.name = 'lottery_state' AND tcf.value = 'finished'")
          .where(
            "EXISTS (
            SELECT 1 FROM topic_custom_fields
            WHERE topic_id = topics.id
            AND name = 'lottery_results'
            AND value IS NOT NULL
          )",
          )
          .includes(:category, :user)
          .order("topics.created_at DESC")

      # Build flat list of packets (only those with winners)
      all_packets = []
      lotteries.each do |lottery|
        lottery_packets = build_lottery_packets(lottery)
        # Only include packets that have a winner
        all_packets.concat(lottery_packets.select { |p| p[:winner].present? })
      end

      # Apply search filter
      if search.present?
        all_packets.select! do |packet|
          packet[:lottery_title].downcase.include?(search.downcase) ||
            packet[:title].downcase.include?(search.downcase)
        end
      end

      # Apply sorting
      all_packets =
        case sort
        when "date_asc"
          all_packets.sort_by { |p| p[:lottery_created_at] }
        when "lottery_asc"
          all_packets.sort_by { |p| [p[:lottery_title].downcase, p[:lottery_created_at]] }
        when "lottery_desc"
          all_packets.sort_by { |p| [p[:lottery_title].downcase, p[:lottery_created_at]] }.reverse
        else # date_desc
          all_packets.sort_by { |p| p[:lottery_created_at] }.reverse
        end

      render json: { packets: all_packets }
    end

    private

    # Build packet data for a lottery
    #
    # @param topic [Topic] The lottery topic
    # @return [Array<Hash>] Array of packet data
    def build_lottery_packets(topic)
      # Get lottery custom fields
      lottery_drawn_at = topic.custom_fields["lottery_drawn_at"]

      # Get all packet posts
      packets =
        Post
          .where(topic_id: topic.id)
          .joins("INNER JOIN post_custom_fields pcf ON pcf.post_id = posts.id")
          .where("pcf.name = 'is_lottery_packet' AND pcf.value = 't'")
          .includes(:user)
          .order(:post_number)

      # Build packet data with lottery context
      packets.map do |packet|
        winner_username = packet.custom_fields["lottery_winner"]
        collected_at = packet.custom_fields["packet_collected_at"]
        erhaltungsbericht_topic_id = packet.custom_fields["erhaltungsbericht_topic_id"]

        # Extract packet title from post
        packet_title = extract_title_from_markdown(packet.raw)

        # Get winner user
        winner = User.find_by(username: winner_username) if winner_username.present?

        # Get erhaltungsbericht topic
        erhaltungsbericht_topic = nil
        if erhaltungsbericht_topic_id.present?
          erhaltungsbericht_topic = Topic.find_by(id: erhaltungsbericht_topic_id)
        end

        {
          # Packet info
          post_id: packet.id,
          post_number: packet.post_number,
          title: packet_title,
          packet_url: "#{topic.relative_url}/#{packet.post_number}",
          # Lottery info
          lottery_id: topic.id,
          lottery_title: topic.title,
          lottery_url: topic.relative_url,
          lottery_created_at: topic.created_at,
          lottery_drawn_at: lottery_drawn_at,
          category: {
            id: topic.category&.id,
            name: topic.category&.name,
            slug: topic.category&.slug,
            color: topic.category&.color,
          },
          # Winner info
          winner:
            if winner
              {
                id: winner.id,
                username: winner.username,
                name: winner.name,
                avatar_template: winner.avatar_template,
              }
            else
              nil
            end,
          collected_at: collected_at,
          won_at: lottery_drawn_at, # Date when winners were drawn
          erhaltungsbericht:
            if erhaltungsbericht_topic
              {
                topic_id: erhaltungsbericht_topic.id,
                title: erhaltungsbericht_topic.title,
                slug: erhaltungsbericht_topic.slug,
                url: erhaltungsbericht_topic.relative_url,
                created_at: erhaltungsbericht_topic.created_at,
              }
            else
              nil
            end,
        }
      end
    end

    # Extract title from markdown heading
    #
    # @param markdown [String] The markdown content
    # @return [String] The extracted title
    def extract_title_from_markdown(markdown)
      # Match markdown headings (# Title or ## Title)
      match = markdown.match(/^#+\s+(.+)$/)
      match ? match[1].strip : "Paket"
    end
  end
end
