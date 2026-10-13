# frozen_string_literal: true

module VzekcVerlosung
  # The forum's side of Herold's app interface: the manifest Herold fetches when
  # the operator registers the forum, and the thread action Herold invokes
  # server-to-server with the raw messages of a mail thread. The action stores
  # the messages and answers with a one-time URL that opens the pre-filled
  # donation offer for the logged-in facilitator.
  class HeroldAppController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    APP_KEY = "de.classic-computing.forum.donations"
    ACTION_PATH = "/vzekc-verlosung/herold/actions/donation-offer"
    SIGNATURE_WINDOW = 300
    MAX_MESSAGES = 100

    skip_before_action :verify_authenticity_token, only: :donation_offer
    skip_before_action :redirect_to_login_if_required, only: %i[manifest donation_offer]
    skip_before_action :check_xhr, :preload_json

    before_action :ensure_configured, only: :donation_offer

    # GET /.well-known/herold-app.json
    #
    # Served without a configured secret: Herold fetches the manifest when the
    # forum is registered and only then issues the secret.
    #
    # @return [JSON] Herold app manifest (API version 1)
    def manifest
      render json: {
               herold_app: 1,
               app_key: APP_KEY,
               name: localized("vzekc_verlosung.herold_app.name"),
               extensions: [
                 {
                   point: "thread.action",
                   id: "donation-offer",
                   label: localized("vzekc_verlosung.herold_app.donation_offer_label"),
                   icon: "gift",
                   scopes: ["thread.raw"],
                   endpoint: ACTION_PATH,
                 },
               ],
             }
    end

    # POST /vzekc-verlosung/herold/actions/donation-offer
    #
    # Receives a signed thread action invocation (multipart: a "context" JSON
    # part and one "message[]" part per raw message) and stores it as a handoff.
    #
    # @return [JSON] {type: "open_url", url} on success, {error} otherwise
    def donation_offer
      return action_error(:unauthorized, "signature_invalid") unless valid_signature?

      context = parse_context
      invocation_id = context["invocation_id"].to_s
      if context["herold_app"] != 1 || invocation_id.blank?
        return action_error(:bad_request, "invalid_context")
      end

      messages = Array.wrap(params[:message]).select { _1.respond_to?(:read) }
      return action_error(:unprocessable_entity, "no_messages") if messages.empty?
      if messages.size > MAX_MESSAGES
        return action_error(:unprocessable_entity, "too_many_messages")
      end

      token = SecureRandom.urlsafe_base64(32)
      EmailHandoff.transaction do
        handoff =
          EmailHandoff.create!(
            token_digest: EmailHandoff.digest(token),
            invocation_id: invocation_id.first(255),
            herold_user_email: context.dig("user", "email").to_s.first(255),
            thread_subject: context.dig("thread", "subject").to_s.first(255),
            expires_at: EmailHandoff::TTL.from_now,
          )
        messages.each_with_index do |file, index|
          handoff.messages.create!(position: index, raw: file.read)
        end
      end

      render json: { type: "open_url", url: "#{Discourse.base_url}/spende-aus-email/#{token}" }
    rescue ActiveRecord::RecordNotUnique
      action_error(:conflict, "duplicate_invocation")
    end

    # GET /spende-aus-email/:token
    #
    # Serves the app shell; the Ember route consumes the token.
    def handoff_page
      render html: "", layout: true
    end

    private

    def ensure_configured
      raise Discourse::NotFound if SiteSetting.vzekc_verlosung_herold_app_secret.blank?
    end

    def localized(key)
      { en: I18n.t(key, locale: :en), de: I18n.t(key, locale: :de) }
    end

    def action_error(status, key)
      render json: { error: I18n.t("vzekc_verlosung.herold_app.errors.#{key}") }, status: status
    end

    def parse_context
      JSON.parse(
        params[:context].respond_to?(:read) ? params[:context].read : params[:context].to_s,
      )
    rescue JSON::ParserError
      {}
    end

    # Herold-Signature: t=<unix seconds>,v1=<hex HMAC-SHA256(secret, "v1:" + t + ":" + body)>
    def valid_signature?
      fields =
        request.headers["Herold-Signature"]
          .to_s
          .split(",")
          .filter_map { |field| field.strip.split("=", 2) if field.include?("=") }
          .to_h
      timestamp = fields["t"].to_s
      signature = fields["v1"].to_s
      return false if timestamp !~ /\A\d+\z/ || signature.blank?
      return false if (Time.zone.now.to_i - timestamp.to_i).abs > SIGNATURE_WINDOW

      expected =
        OpenSSL::HMAC.hexdigest(
          "SHA256",
          SiteSetting.vzekc_verlosung_herold_app_secret,
          "v1:#{timestamp}:#{request.raw_post}",
        )
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end
  end
end
