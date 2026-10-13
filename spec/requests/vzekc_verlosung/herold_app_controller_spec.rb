# frozen_string_literal: true

require "rails_helper"

describe VzekcVerlosung::HeroldAppController do
  let(:secret) { "c2VjcmV0LWZvci10ZXN0cy0zMi1ieXRlcy1sb25nLW9r" }
  let(:boundary) { "heroldboundary" }
  let(:eml) do
    "From: Erika Beispiel <erika@example.com>\r\nSubject: Rechner\r\n\r\nEin Rechner.\r\n"
  end
  let(:action_path) { "/vzekc-verlosung/herold/actions/donation-offer" }

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_herold_app_secret = secret
  end

  def multipart_body(messages, invocation_id: SecureRandom.uuid, api: 1)
    context = {
      herold_app: api,
      invocation_id: invocation_id,
      user: {
        email: "alice@example.local",
      },
      thread: {
        subject: "Rechner",
      },
    }
    parts = [
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"context\"\r\n" \
        "Content-Type: application/json\r\n\r\n#{context.to_json}\r\n",
    ]
    messages.each_with_index do |message, index|
      parts << "--#{boundary}\r\nContent-Disposition: form-data; name=\"message[]\"; " \
        "filename=\"#{index + 1}.eml\"\r\nContent-Type: message/rfc822\r\n\r\n#{message}\r\n"
    end
    parts.join + "--#{boundary}--\r\n"
  end

  def invoke(body, timestamp: Time.zone.now.to_i, key: secret, invocation_id: SecureRandom.uuid)
    signature = OpenSSL::HMAC.hexdigest("SHA256", key, "v1:#{timestamp}:#{body}")
    post action_path,
         params: body,
         headers: {
           "CONTENT_TYPE" => "multipart/form-data; boundary=#{boundary}",
           "Herold-Signature" => "t=#{timestamp},v1=#{signature}",
           "Herold-Invocation-Id" => invocation_id,
         }
  end

  describe "#manifest" do
    it "publishes the donation offer thread action" do
      get "/.well-known/herold-app.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["herold_app"]).to eq(1)
      expect(response.parsed_body["extensions"].first).to include(
        "point" => "thread.action",
        "scopes" => ["thread.raw"],
        "endpoint" => action_path,
      )
    end

    it "is reachable on a login-required site" do
      SiteSetting.login_required = true

      get "/.well-known/herold-app.json"

      expect(response.status).to eq(200)
    end

    it "is served before a secret is configured" do
      SiteSetting.vzekc_verlosung_herold_app_secret = ""

      get "/.well-known/herold-app.json"

      expect(response.status).to eq(200)
    end
  end

  describe "#donation_offer" do
    it "stores the messages and returns a one-time URL" do
      expect { invoke(multipart_body([eml, eml.sub("Ein", "Noch ein")])) }.to change {
        VzekcVerlosung::EmailHandoff.count
      }.by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["type"]).to eq("open_url")
      token = response.parsed_body["url"][%r{/spende-aus-email/([\w-]+)\z}, 1]
      expect(VzekcVerlosung::EmailHandoff.consume(token) { |raws| raws.size }).to eq(2)
    end

    it "accepts the invocation on a login-required site" do
      SiteSetting.login_required = true

      invoke(multipart_body([eml]))

      expect(response.status).to eq(200)
    end

    it "returns 404 while no secret is configured" do
      SiteSetting.vzekc_verlosung_herold_app_secret = ""

      invoke(multipart_body([eml]))

      expect(response.status).to eq(404)
    end

    it "rejects a wrong signature" do
      invoke(multipart_body([eml]), key: "other")

      expect(response.status).to eq(401)
      expect(VzekcVerlosung::EmailHandoff.count).to eq(0)
    end

    it "rejects a stale timestamp" do
      invoke(multipart_body([eml]), timestamp: 10.minutes.ago.to_i)

      expect(response.status).to eq(401)
    end

    it "rejects a repeated invocation id" do
      invoke(multipart_body([eml], invocation_id: "inv-1"))
      invoke(multipart_body([eml], invocation_id: "inv-1"), invocation_id: "other-header")

      expect(response.status).to eq(409)
    end

    it "rejects a context without invocation id" do
      invoke(multipart_body([eml], invocation_id: nil))

      expect(response.status).to eq(400)
    end

    it "rejects an unsupported API version" do
      invoke(multipart_body([eml], api: 2))

      expect(response.status).to eq(400)
    end

    it "rejects a request without messages" do
      invoke(multipart_body([]))

      expect(response.status).to eq(422)
    end
  end

  describe "#handoff_page" do
    it "serves the app shell to anonymous visitors" do
      get "/spende-aus-email/some-token"

      expect(response.status).to eq(200)
    end
  end

  describe "with a handoff token and no session" do
    it "requires a logged-in user" do
      invoke(multipart_body([eml]))
      handoff_token = response.parsed_body["url"][%r{/spende-aus-email/([\w-]+)\z}, 1]

      post "/vzekc-verlosung/donations/import-email.json", params: { handoff_token: handoff_token }

      expect(response.status).to eq(403)
      expect(VzekcVerlosung::EmailHandoff.count).to eq(1)
    end
  end

  describe "with a handoff token" do
    fab!(:facilitator, :user)

    let(:token) do
      invoke(multipart_body([eml]))
      response.parsed_body["url"][%r{/spende-aus-email/([\w-]+)\z}, 1]
    end

    before { sign_in(facilitator) }

    it "imports the handed-over thread once" do
      post "/vzekc-verlosung/donations/import-email.json", params: { handoff_token: token }

      expect(response.status).to eq(200)
      expect(response.parsed_body["donor"]["email"]).to eq("erika@example.com")

      post "/vzekc-verlosung/donations/import-email.json", params: { handoff_token: token }

      expect(response.status).to eq(410)
    end

    it "keeps the handoff when the import finds no message" do
      VzekcVerlosung::DonationEmailImport.any_instance.stubs(:call).returns(nil)

      post "/vzekc-verlosung/donations/import-email.json", params: { handoff_token: token }

      expect(response.status).to eq(422)
      expect(VzekcVerlosung::EmailHandoff.count).to eq(1)
    end

    it "refuses an expired handoff" do
      handoff_token = token
      freeze_time(VzekcVerlosung::EmailHandoff::TTL.from_now + 1.second)

      post "/vzekc-verlosung/donations/import-email.json", params: { handoff_token: handoff_token }

      expect(response.status).to eq(410)
    end
  end
end
