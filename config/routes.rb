# frozen_string_literal: true

VzekcVerlosung::Engine.routes.draw do
  get "/examples" => "examples#index"
  get "/history" => "lottery_history#index"
  post "/lotteries" => "lotteries#create"
  get "/lotteries/:topic_id/packets" => "lotteries#packets"
  put "/lotteries/:topic_id/publish" => "lotteries#publish"
  put "/lotteries/:topic_id/end-early" => "lotteries#end_early"
  get "/lotteries/:topic_id/drawing-data" => "lotteries#drawing_data"
  post "/lotteries/:topic_id/draw" => "lotteries#draw"
  post "/lotteries/:topic_id/draw-manual" => "lotteries#draw_manual"
  get "/lotteries/:topic_id/results.json" => "lotteries#results"

  post "/tickets" => "tickets#create"
  delete "/tickets/:post_id" => "tickets#destroy"
  get "/tickets/packet-status/:post_id" => "tickets#packet_status"
  post "/packets/:post_id/mark-collected" => "tickets#mark_collected"
  post "/packets/:post_id/create-erhaltungsbericht" => "tickets#create_erhaltungsbericht"

  # Donation routes
  post "/donations" => "donations#create"
  get "/donations/:id" => "donations#show"
  put "/donations/:id/publish" => "donations#publish"
  put "/donations/:id/close" => "donations#close"

  # Pickup offer routes
  post "/donations/:donation_id/pickup-offers" => "pickup_offers#create"
  delete "/pickup-offers/:id" => "pickup_offers#destroy"
  get "/donations/:donation_id/pickup-offers" => "pickup_offers#index"
  put "/pickup-offers/:id/assign" => "pickup_offers#assign"
  put "/pickup-offers/:id/mark-picked-up" => "pickup_offers#mark_picked_up"
end

Discourse::Application.routes.draw { mount ::VzekcVerlosung::Engine, at: "vzekc-verlosung" }
