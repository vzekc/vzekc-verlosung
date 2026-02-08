# frozen_string_literal: true

require "rails_helper"

describe VzekcVerlosung::NewContentController do
  fab!(:user)
  fab!(:other_user, :user)
  fab!(:category)

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id = category.id.to_s
  end

  describe "#index" do
    context "when not logged in" do
      it "returns 403" do
        get "/vzekc-verlosung/has-new-content.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in" do
      before { sign_in(user) }

      it "returns all false when there is no content" do
        get "/vzekc-verlosung/has-new-content.json"
        expect(response.status).to eq(200)

        json = response.parsed_body
        expect(json["donations"]).to eq(false)
        expect(json["lotteries"]).to eq(false)
        expect(json["erhaltungsberichte"]).to eq(false)
        expect(json["merch_packets"]).to eq(false)
      end

      context "with unread donations" do
        fab!(:donation_topic) { Fabricate(:topic, created_at: 1.day.ago) }
        fab!(:donation) do
          Fabricate(:donation, state: "open", topic: donation_topic, published_at: 1.day.ago)
        end

        it "returns true for donations when user has not opened the topic" do
          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["donations"]).to eq(true)
        end

        it "returns false for donations when user has opened the topic" do
          TopicUser.create!(
            user_id: user.id,
            topic_id: donation_topic.id,
            first_visited_at: Time.zone.now,
          )

          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["donations"]).to eq(false)
        end

        it "ignores draft donations" do
          donation.update!(state: "draft")

          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["donations"]).to eq(false)
        end

        it "ignores donations older than 4 weeks" do
          donation_topic.update!(created_at: 5.weeks.ago)

          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["donations"]).to eq(false)
        end
      end

      context "with unread lotteries" do
        fab!(:lottery_topic, :topic)
        fab!(:lottery) { Fabricate(:lottery, topic: lottery_topic, state: "active") }

        it "returns true for lotteries when user has not opened the topic" do
          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["lotteries"]).to eq(true)
        end

        it "returns false for lotteries when user has opened the topic" do
          TopicUser.create!(
            user_id: user.id,
            topic_id: lottery_topic.id,
            first_visited_at: Time.zone.now,
          )

          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["lotteries"]).to eq(false)
        end

        it "ignores finished lotteries" do
          lottery.update!(state: "finished")

          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["lotteries"]).to eq(false)
        end
      end

      context "with unread erhaltungsberichte" do
        fab!(:eb_topic) { Fabricate(:topic, category: category, created_at: 1.day.ago) }

        it "returns true when user has not opened the topic" do
          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["erhaltungsberichte"]).to eq(true)
        end

        it "returns false when user has opened the topic" do
          TopicUser.create!(
            user_id: user.id,
            topic_id: eb_topic.id,
            first_visited_at: Time.zone.now,
          )

          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["erhaltungsberichte"]).to eq(false)
        end

        it "ignores topics older than 4 weeks" do
          eb_topic.update!(created_at: 5.weeks.ago)

          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["erhaltungsberichte"]).to eq(false)
        end

        it "returns false when category is not configured" do
          SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id = ""

          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["erhaltungsberichte"]).to eq(false)
        end
      end

      context "with merch packets" do
        fab!(:merch_handler, :user)
        fab!(:merch_handlers_group) { Fabricate(:group, name: "merch-handlers") }
        fab!(:donation) { Fabricate(:donation, state: "picked_up") }
        fab!(:pending_packet) { Fabricate(:merch_packet, donation: donation) }

        before { SiteSetting.vzekc_verlosung_merch_handlers_group_name = "merch-handlers" }

        it "returns false for regular users" do
          get "/vzekc-verlosung/has-new-content.json"

          json = response.parsed_body
          expect(json["merch_packets"]).to eq(false)
        end

        context "when logged in as merch handler" do
          before do
            merch_handlers_group.add(merch_handler)
            sign_in(merch_handler)
          end

          it "returns true when pending packets exist for picked-up donations" do
            get "/vzekc-verlosung/has-new-content.json"

            json = response.parsed_body
            expect(json["merch_packets"]).to eq(true)
          end

          it "returns false when donation is not yet picked up" do
            donation.update!(state: "open")

            get "/vzekc-verlosung/has-new-content.json"

            json = response.parsed_body
            expect(json["merch_packets"]).to eq(false)
          end

          it "returns true when donation is closed" do
            donation.update!(state: "closed")

            get "/vzekc-verlosung/has-new-content.json"

            json = response.parsed_body
            expect(json["merch_packets"]).to eq(true)
          end

          it "returns false when no pending packets exist" do
            pending_packet.update!(state: "shipped", shipped_at: Time.zone.now)

            get "/vzekc-verlosung/has-new-content.json"

            json = response.parsed_body
            expect(json["merch_packets"]).to eq(false)
          end
        end
      end
    end
  end
end
