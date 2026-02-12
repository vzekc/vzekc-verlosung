# frozen_string_literal: true

require "rails_helper"

RSpec.describe VzekcVerlosung::NotificationLogsController do
  fab!(:admin)
  fab!(:user)
  fab!(:another_user, :user)
  fab!(:lottery_category, :category)

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_category_id = lottery_category.id.to_s
  end

  describe "GET /vzekc-verlosung/admin/notification-logs" do
    context "when not logged in" do
      it "returns 403" do
        get "/vzekc-verlosung/admin/notification-logs.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as regular user" do
      before { sign_in(user) }

      it "returns 403" do
        get "/vzekc-verlosung/admin/notification-logs.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as admin" do
      before { sign_in(admin) }

      it "returns empty list when no logs exist" do
        get "/vzekc-verlosung/admin/notification-logs.json"
        expect(response.status).to eq(200)

        json = response.parsed_body
        expect(json["notification_logs"]).to eq([])
        expect(json["total_count"]).to eq(0)
        expect(json["page"]).to eq(1)
        expect(json).to have_key("notification_types")
        expect(json).to have_key("delivery_methods")
      end

      context "with notification logs" do
        fab!(:log1) do
          VzekcVerlosung::NotificationLog.create!(
            recipient: user,
            notification_type: "lottery_won",
            delivery_method: "in_app",
            success: true,
          )
        end
        fab!(:log2) do
          VzekcVerlosung::NotificationLog.create!(
            recipient: another_user,
            notification_type: "ticket_bought",
            delivery_method: "pm",
            success: false,
            error_message: "User has PMs disabled",
          )
        end

        it "returns all logs" do
          get "/vzekc-verlosung/admin/notification-logs.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["notification_logs"].length).to eq(2)
          expect(json["total_count"]).to eq(2)
        end

        it "filters by username" do
          get "/vzekc-verlosung/admin/notification-logs.json", params: { username: user.username }
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["notification_logs"].length).to eq(1)
          expect(json["notification_logs"][0]["recipient"]["username"]).to eq(user.username)
        end

        it "filters by notification type" do
          get "/vzekc-verlosung/admin/notification-logs.json",
              params: {
                notification_type: "lottery_won",
              }
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["notification_logs"].length).to eq(1)
          expect(json["notification_logs"][0]["notification_type"]).to eq("lottery_won")
        end

        it "filters by delivery method" do
          get "/vzekc-verlosung/admin/notification-logs.json", params: { delivery_method: "pm" }
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["notification_logs"].length).to eq(1)
          expect(json["notification_logs"][0]["delivery_method"]).to eq("pm")
        end

        it "filters by success status" do
          get "/vzekc-verlosung/admin/notification-logs.json", params: { success: "false" }
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["notification_logs"].length).to eq(1)
          expect(json["notification_logs"][0]["success"]).to eq(false)
          expect(json["notification_logs"][0]["error_message"]).to eq("User has PMs disabled")
        end

        it "includes payload for admin" do
          log1.update!(payload: { packet_id: 123 })

          get "/vzekc-verlosung/admin/notification-logs.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          log_with_payload =
            json["notification_logs"].find { |l| l["notification_type"] == "lottery_won" }
          expect(log_with_payload["payload"]).to eq({ "packet_id" => 123 })
        end
      end
    end
  end

  describe "GET /vzekc-verlosung/users/:username/notification-logs" do
    context "when not logged in" do
      it "returns 403" do
        get "/vzekc-verlosung/users/#{user.username}/notification-logs.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as different user" do
      before { sign_in(another_user) }

      it "returns 403" do
        get "/vzekc-verlosung/users/#{user.username}/notification-logs.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as the user" do
      before { sign_in(user) }

      it "returns empty list when no logs exist" do
        get "/vzekc-verlosung/users/#{user.username}/notification-logs.json"
        expect(response.status).to eq(200)

        json = response.parsed_body
        expect(json["notification_logs"]).to eq([])
        expect(json["total_count"]).to eq(0)
      end

      context "with notification logs" do
        fab!(:log_for_user) do
          VzekcVerlosung::NotificationLog.create!(
            recipient: user,
            notification_type: "lottery_won",
            delivery_method: "in_app",
            success: true,
          )
        end
        fab!(:log_for_other) do
          VzekcVerlosung::NotificationLog.create!(
            recipient: another_user,
            notification_type: "ticket_bought",
            delivery_method: "pm",
            success: true,
          )
        end

        it "returns only user's own notifications" do
          get "/vzekc-verlosung/users/#{user.username}/notification-logs.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["notification_logs"].length).to eq(1)
          expect(json["notification_logs"][0]["recipient"]["username"]).to eq(user.username)
        end

        it "does not include payload" do
          log_for_user.update!(payload: { packet_id: 123 })

          get "/vzekc-verlosung/users/#{user.username}/notification-logs.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["notification_logs"][0]).not_to have_key("payload")
        end
      end

      context "with lottery created by user" do
        fab!(:lottery_topic) { Fabricate(:topic, category: lottery_category, user: user) }
        fab!(:lottery) do
          VzekcVerlosung::Lottery.create!(
            topic: lottery_topic,
            state: "active",
            drawing_mode: "automatic",
            ends_at: 7.days.from_now,
          )
        end
        fab!(:notification_for_lottery) do
          VzekcVerlosung::NotificationLog.create!(
            recipient: another_user,
            lottery: lottery,
            notification_type: "ticket_bought",
            delivery_method: "in_app",
            success: true,
          )
        end

        it "includes notifications from lotteries user created" do
          get "/vzekc-verlosung/users/#{user.username}/notification-logs.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["notification_logs"].length).to eq(1)
          expect(json["notification_logs"][0]["notification_type"]).to eq("ticket_bought")
          expect(json["notification_logs"][0]["lottery"]["id"]).to eq(lottery.id)
        end
      end
    end

    context "when logged in as admin" do
      before { sign_in(admin) }

      it "can view any user's notifications" do
        VzekcVerlosung::NotificationLog.create!(
          recipient: user,
          notification_type: "lottery_won",
          delivery_method: "in_app",
          success: true,
        )

        get "/vzekc-verlosung/users/#{user.username}/notification-logs.json"
        expect(response.status).to eq(200)

        json = response.parsed_body
        expect(json["notification_logs"].length).to eq(1)
      end
    end

    context "when user does not exist" do
      before { sign_in(admin) }

      it "returns 404" do
        get "/vzekc-verlosung/users/nonexistent_user/notification-logs.json"
        expect(response.status).to eq(404)
      end
    end
  end
end
