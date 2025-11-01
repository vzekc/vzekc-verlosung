# frozen_string_literal: true

VzekcVerlosung::Engine.routes.draw do
  get "/examples" => "examples#index"
  post "/lotteries" => "lotteries#create"
  get "/lotteries/:topic_id/packets" => "lotteries#packets"
  put "/lotteries/:topic_id/publish" => "lotteries#publish"

  post "/tickets" => "tickets#create"
  delete "/tickets/:post_id" => "tickets#destroy"
  get "/tickets/packet-status/:post_id" => "tickets#packet_status"
end

Discourse::Application.routes.draw { mount ::VzekcVerlosung::Engine, at: "vzekc-verlosung" }
