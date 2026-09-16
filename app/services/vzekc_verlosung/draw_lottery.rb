# frozen_string_literal: true

module VzekcVerlosung
  # Finishes a lottery with a set of drawing results: stores the results, marks
  # the packets and their winners, and notifies participants. The controller
  # applies results after verifying the client's drawing; the end-of-lottery
  # jobs apply results they computed themselves for lotteries that draw
  # automatically when they end.
  #
  # @example Draw an ended lottery without user interaction
  #   VzekcVerlosung::DrawLottery.auto_draw!(lottery)
  #
  # @example Apply verified results from the drawing modal
  #   VzekcVerlosung::DrawLottery.apply_results!(lottery, results)
  #
  module DrawLottery
    # Raised when results are applied to a lottery that has already been drawn,
    # for example by the owner while the automatic drawing was running.
    class AlreadyDrawnError < StandardError
    end

    # Draws an ended lottery that is configured to draw on end and tells the
    # owner what happened. A lottery without any tickets is finished without
    # participants. Drawing errors are logged and the lottery is left ready to
    # draw, so the owner is asked to draw manually.
    #
    # @param lottery [VzekcVerlosung::Lottery]
    # @return [Boolean] true when the lottery is drawn or finished afterwards
    def self.auto_draw!(lottery)
      return false unless lottery.auto_draws_on_end?
      return false unless lottery.active? && lottery.ended? && !lottery.drawn?

      topic = lottery.topic
      owner = topic&.user
      return false unless owner

      unless lottery.has_drawable_tickets?
        lottery.finish_without_participants!
        NotificationService.notify(
          :no_participants_reminder,
          recipient: owner,
          context: {
            lottery: lottery,
          },
        )
        return true
      end

      begin
        results = JavascriptLotteryDrawer.draw(drawing_data(lottery))
        apply_results!(lottery, results)
      rescue AlreadyDrawnError
        return true
      rescue StandardError => e
        Rails.logger.error(
          "[VzekcVerlosung] Automatic drawing failed for lottery #{lottery.id} " \
            "(topic #{topic.id}): #{e.message}",
        )
        return false
      end

      NotificationService.notify(
        :lottery_auto_drawn,
        recipient: owner,
        context: {
          lottery: lottery,
        },
      )

      true
    end

    # Builds the input for lottery.js from the lottery's packets and tickets.
    # The Abholerpaket is excluded because it is assigned to the picker.
    #
    # @param lottery [VzekcVerlosung::Lottery]
    # @return [Hash] { title:, timestamp:, packets: [{ id:, title:, participants:, quantity: }] }
    def self.drawing_data(lottery)
      topic = lottery.topic

      lottery_packets =
        lottery
          .lottery_packets
          .where(abholerpaket: false)
          .joins(:post)
          .includes(lottery_tickets: :user)
          .order("posts.post_number")

      packets =
        lottery_packets.map do |packet|
          participants =
            packet
              .lottery_tickets
              .group_by(&:user)
              .map { |user, user_tickets| { name: user.username, tickets: user_tickets.count } }

          {
            id: packet.post_id,
            title: packet.title,
            participants: participants,
            quantity: packet.quantity,
          }
        end

      # The RNG is seeded with the publication time, derived from the deadline
      duration_days = lottery.duration_days || 14
      published_at = lottery.ends_at ? lottery.ends_at - duration_days.days : topic.created_at

      { title: topic.title, timestamp: published_at.iso8601, packets: packets }
    end

    # Stores results, marks packets and winners, finishes the lottery, and
    # notifies participants, winners, and non-winners. The state changes run in
    # one transaction holding a row lock on the lottery, so concurrent drawings
    # of the same lottery are serialized and the second one raises
    # AlreadyDrawnError.
    #
    # @param lottery [VzekcVerlosung::Lottery]
    # @param results [Hash] results as produced by lottery.js draw() or by the
    #   manual drawing; "drawings" and "packets" are index-aligned arrays
    # @raise [AlreadyDrawnError] when the lottery has been drawn in the meantime
    def self.apply_results!(lottery, results)
      topic = lottery.topic
      drawn_at = Time.zone.now

      lottery.with_lock do
        raise AlreadyDrawnError if lottery.drawn?

        lottery.finish!
        lottery.mark_drawn!(results)

        results["drawings"].each_with_index do |drawing, index|
          packet_data = results["packets"][index]
          next unless packet_data

          packet = lottery.lottery_packets.find { |p| p.post_id == packet_data["id"] }
          next unless packet

          winners = drawing["winners"] || []

          if winners.compact.any?
            packet.mark_drawn!

            winners.each_with_index do |winner_username, instance_idx|
              next if winner_username.blank?
              winner_user = User.find_by(username: winner_username)
              if winner_user
                packet.mark_winner!(winner_user, drawn_at, instance_number: instance_idx + 1)
              end
            end
          else
            packet.mark_no_tickets!
          end
        end

        # Packets absent from the results had no tickets
        lottery
          .lottery_packets
          .where(abholerpaket: false, state: "pending")
          .find_each { |packet| packet.mark_no_tickets! }
      end

      notify_lottery_drawn(topic)
      notify_winners(lottery, results)
      notify_non_winners(topic, results)
    end

    # Notify all users with tickets that winners have been drawn
    def self.notify_lottery_drawn(topic)
      recipients = User.where(id: participant_user_ids(topic))

      NotificationService.notify_batch(
        :lottery_drawn,
        recipients: recipients,
        context: {
          topic: topic,
        },
      )
    end

    # Notify winners in-app per packet and by one PM listing all packets won
    def self.notify_winners(lottery, results)
      topic = lottery.topic
      tickets_by_user = tickets_by_user(topic)

      winners_packets = Hash.new { |h, k| h[k] = [] }
      won_titles_by_user = Hash.new { |h, k| h[k] = Set.new }

      results["drawings"].each_with_index do |drawing, index|
        packet_title = drawing["text"]
        winner_usernames = drawing["winners"] || []

        packet_data = results["packets"][index]
        next unless packet_data

        lottery_packet = lottery.lottery_packets.find { |p| p.post_id == packet_data["id"] }
        next unless lottery_packet

        packet_post = lottery_packet.post
        post_number = packet_post ? packet_post.post_number : 1

        winner_usernames.each_with_index do |winner_username, instance_idx|
          next if winner_username.blank?

          winner_user = User.find_by(username: winner_username)
          next unless winner_user

          won_titles_by_user[winner_user.id] << lottery_packet.title
          lost_packet_titles =
            (tickets_by_user[winner_user.id] || []) - won_titles_by_user[winner_user.id].to_a

          NotificationService.notify(
            :lottery_won,
            recipient: winner_user,
            context: {
              topic: topic,
              packet: lottery_packet,
              instance_number: instance_idx + 1,
              total_instances: winner_usernames.length,
              lost_packet_titles: lost_packet_titles,
            },
          )

          winners_packets[winner_user] << {
            title: packet_title,
            instance_number: instance_idx + 1,
            total_instances: winner_usernames.length,
            post_number: post_number,
            post: packet_post,
          }
        end
      end

      winners_packets.each do |winner_user, packets|
        service =
          NotificationService.notify_and_return(
            :winner_pm,
            recipient: winner_user,
            context: {
              topic: topic,
              packets: packets,
            },
          )

        pm_topic_id = service.pm_post&.topic_id
        next unless pm_topic_id

        LotteryPacketWinner
          .joins(:lottery_packet)
          .where(
            winner_user_id: winner_user.id,
            vzekc_verlosung_lottery_packets: {
              lottery_id: lottery.id,
            },
          )
          .update_all(winner_pm_topic_id: pm_topic_id)
      end
    end

    # Notify participants who did not win anything
    def self.notify_non_winners(topic, results)
      winner_usernames = results["drawings"].flat_map { |drawing| drawing["winners"] || [] }.compact

      non_winners =
        User
          .where(id: participant_user_ids(topic))
          .reject { |u| winner_usernames.include?(u.username) }

      tickets_by_user = tickets_by_user(topic)

      non_winners.each do |user|
        NotificationService.notify(
          :did_not_win,
          recipient: user,
          context: {
            topic: topic,
            packet_titles: tickets_by_user[user.id] || [],
          },
        )
      end
    end

    # @return [Hash] { user_id => ["Packet Title A", "Packet Title B"], ... }
    def self.tickets_by_user(topic)
      LotteryTicket
        .joins(:post)
        .joins(
          "INNER JOIN vzekc_verlosung_lottery_packets ON vzekc_verlosung_lottery_packets.post_id = posts.id",
        )
        .where(posts: { topic_id: topic.id })
        .where("vzekc_verlosung_lottery_packets.abholerpaket = false")
        .pluck(:user_id, "vzekc_verlosung_lottery_packets.title")
        .group_by(&:first)
        .transform_values { |pairs| pairs.map(&:last) }
    end

    # @return [Array<Integer>] ids of all users holding tickets in this lottery
    def self.participant_user_ids(topic)
      LotteryTicket.joins(:post).where(posts: { topic_id: topic.id }).distinct.pluck(:user_id)
    end

    private_class_method :notify_lottery_drawn,
                         :notify_winners,
                         :notify_non_winners,
                         :tickets_by_user,
                         :participant_user_ids
  end
end
