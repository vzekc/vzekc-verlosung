# frozen_string_literal: true

module VzekcVerlosung
  class NotificationLogsController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_admin, only: [:admin_index]

    # GET /vzekc-verlosung/admin/notification-logs.json
    #
    # Returns all notification logs with filtering (admin only)
    #
    # @param page [Integer] Page number (default: 1)
    # @param per_page [Integer] Items per page (default: 50, max: 100)
    # @param username [String] Filter by recipient username
    # @param notification_type [String] Filter by notification type
    # @param delivery_method [String] Filter by delivery method (in_app, pm)
    # @param success [String] Filter by success status ("true" or "false")
    # @param from_date [String] Filter from date (ISO 8601)
    # @param to_date [String] Filter to date (ISO 8601)
    #
    # @return [JSON] Paginated notification logs with metadata
    def admin_index
      logs =
        NotificationLog.recent.includes(:recipient, :actor, :lottery, :donation, :lottery_packet)

      logs = apply_filters(logs)

      # Pagination
      page = (params[:page] || 1).to_i
      per_page = [(params[:per_page] || 50).to_i, 100].min
      offset = (page - 1) * per_page

      total_count = logs.count
      logs = logs.offset(offset).limit(per_page)

      render json: {
               notification_logs: serialize_logs(logs, include_payload: true),
               total_count: total_count,
               page: page,
               per_page: per_page,
               notification_types: distinct_notification_types,
               delivery_methods: %w[in_app pm],
             }
    end

    # GET /vzekc-verlosung/users/:username/notification-logs.json
    #
    # Returns notification logs for a user:
    # - All logs where they are the recipient
    # - All logs from lotteries they created
    #
    # @param username [String] Username to fetch logs for
    # @param page [Integer] Page number (default: 1)
    # @param per_page [Integer] Items per page (default: 50, max: 100)
    # @param notification_type [String] Filter by notification type
    # @param delivery_method [String] Filter by delivery method
    # @param success [String] Filter by success status
    #
    # @return [JSON] Paginated notification logs
    def user_index
      user = User.find_by_username(params[:username])
      raise Discourse::NotFound unless user

      # Users can only view their own notifications
      raise Discourse::InvalidAccess unless current_user.id == user.id || current_user.admin?

      # Get lottery IDs created by this user
      user_lottery_ids = Lottery.joins(:topic).where(topics: { user_id: user.id }).pluck(:id)

      # Fetch logs where user is recipient OR logs from their lotteries
      logs =
        NotificationLog
          .recent
          .includes(:recipient, :actor, :lottery, :donation, :lottery_packet)
          .where(
            "recipient_user_id = ? OR lottery_id IN (?)",
            user.id,
            user_lottery_ids.presence || [-1],
          )

      logs = apply_filters(logs, exclude_username: true)

      # Pagination
      page = (params[:page] || 1).to_i
      per_page = [(params[:per_page] || 50).to_i, 100].min
      offset = (page - 1) * per_page

      total_count = logs.count
      logs = logs.offset(offset).limit(per_page)

      render json: {
               notification_logs: serialize_logs(logs, include_payload: false),
               total_count: total_count,
               page: page,
               per_page: per_page,
             }
    end

    private

    def ensure_admin
      raise Discourse::InvalidAccess unless current_user.admin?
    end

    def apply_filters(logs, exclude_username: false)
      # Filter by recipient username (admin only)
      if !exclude_username && params[:username].present?
        user = User.find_by_username(params[:username])
        logs = logs.where(recipient_user_id: user&.id || -1)
      end

      # Filter by notification type
      if params[:notification_type].present?
        logs = logs.where(notification_type: params[:notification_type])
      end

      # Filter by delivery method
      if params[:delivery_method].present?
        logs = logs.where(delivery_method: params[:delivery_method])
      end

      # Filter by success status
      logs = logs.where(success: params[:success] == "true") if params[:success].present?

      # Filter by date range
      if params[:from_date].present?
        logs = logs.where("created_at >= ?", Time.zone.parse(params[:from_date]).beginning_of_day)
      end

      if params[:to_date].present?
        logs = logs.where("created_at <= ?", Time.zone.parse(params[:to_date]).end_of_day)
      end

      logs
    end

    def serialize_logs(logs, include_payload:)
      logs.map do |log|
        data = {
          id: log.id,
          notification_type: log.notification_type,
          delivery_method: log.delivery_method,
          success: log.success,
          error_message: log.error_message,
          created_at: log.created_at,
          recipient: serialize_user(log.recipient),
          actor: log.actor ? serialize_user(log.actor) : nil,
        }

        # Include lottery info if present
        if log.lottery
          data[:lottery] = {
            id: log.lottery.id,
            topic_id: log.lottery.topic_id,
            title: log.lottery.topic&.title,
            url: log.lottery.topic&.relative_url,
          }
        end

        # Include donation info if present
        if log.donation
          data[:donation] = {
            id: log.donation.id,
            topic_id: log.donation.topic_id,
            title: log.donation.topic&.title,
            url: log.donation.topic&.relative_url,
          }
        end

        # Include packet info if present
        if log.lottery_packet
          data[:packet] = {
            id: log.lottery_packet.id,
            post_id: log.lottery_packet.post_id,
            title: log.lottery_packet.title,
          }
        end

        # Include payload for admin view only
        data[:payload] = log.payload if include_payload

        data
      end
    end

    def serialize_user(user)
      return nil unless user
      {
        id: user.id,
        username: user.username,
        name: user.name,
        avatar_template: user.avatar_template,
      }
    end

    def distinct_notification_types
      NotificationLog.distinct.pluck(:notification_type).sort
    end
  end
end
