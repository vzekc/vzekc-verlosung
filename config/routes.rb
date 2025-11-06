# frozen_string_literal: true

VzekcVerlosung::Engine.routes.draw do
  get "/examples" => "examples#index"
  post "/lotteries" => "lotteries#create"
  get "/lotteries/:topic_id/packets" => "lotteries#packets"
  put "/lotteries/:topic_id/publish" => "lotteries#publish"
  put "/lotteries/:topic_id/end-early" => "lotteries#end_early"
  get "/lotteries/:topic_id/drawing-data" => "lotteries#drawing_data"
  post "/lotteries/:topic_id/draw" => "lotteries#draw"
  get "/lotteries/:topic_id/results.json" => "lotteries#results"

  post "/tickets" => "tickets#create"
  delete "/tickets/:post_id" => "tickets#destroy"
  get "/tickets/packet-status/:post_id" => "tickets#packet_status"
  post "/packets/:post_id/mark-collected" => "tickets#mark_collected"
end

Discourse::Application.routes.draw { mount ::VzekcVerlosung::Engine, at: "vzekc-verlosung" }
