# frozen_string_literal: true

VzekcVerlosung::Engine.routes.draw do
  get "/has-new-content" => "new_content#index"
  get "/examples" => "examples#index"
  get "/users/:username" => "user_stats#show"
  get "/history" => "lottery_history#index"
  get "/history/stats" => "lottery_history#stats"
  get "/history/leaderboard" => "lottery_history#leaderboard"
  get "/history/packets" => "lottery_history#packets"
  get "/history/lotteries" => "lottery_history#lotteries"
  get "/active" => "active_lotteries#index"
  get "/active-donations" => "active_donations#index"
  post "/lotteries" => "lotteries#create"
  get "/lotteries/:topic_id/packets" => "lotteries#packets"
  put "/lotteries/:topic_id/end-early" => "lotteries#end_early"
  get "/lotteries/:topic_id/drawing-data" => "lotteries#drawing_data"
  post "/lotteries/:topic_id/draw" => "lotteries#draw"
  post "/lotteries/:topic_id/draw-manual" => "lotteries#draw_manual"
  get "/lotteries/:topic_id/results.json" => "lotteries#results"

  post "/tickets" => "tickets#create"
  delete "/tickets/:post_id" => "tickets#destroy"
  get "/tickets/packet-status/:post_id" => "tickets#packet_status"
  post "/packets/:post_id/mark-collected" => "tickets#mark_collected"
  post "/packets/:post_id/mark-shipped" => "tickets#mark_shipped"
  post "/packets/:post_id/mark-handed-over" => "tickets#mark_handed_over"
  post "/packets/:post_id/create-erhaltungsbericht" => "tickets#create_erhaltungsbericht"
  put "/packets/:post_id/note" => "tickets#update_note"
  put "/packets/:post_id/toggle-notifications" => "tickets#toggle_notifications"

  # Donation routes
  post "/donations" => "donations#create"
  get "/donations/pending" => "donations#pending"
  get "/donations/:id" => "donations#show"
  put "/donations/:id/publish" => "donations#publish"
  put "/donations/:id/close" => "donations#close"

  # Pickup offer routes
  post "/donations/:donation_id/pickup-offers" => "pickup_offers#create"
  delete "/pickup-offers/:id" => "pickup_offers#destroy"
  get "/donations/:donation_id/pickup-offers" => "pickup_offers#index"
  put "/pickup-offers/:id/assign" => "pickup_offers#assign"
  put "/pickup-offers/:id/mark-picked-up" => "pickup_offers#mark_picked_up"

  # Lottery interest routes
  post "/donations/:donation_id/lottery-interests" => "lottery_interests#create"
  delete "/lottery-interests/:id" => "lottery_interests#destroy"
  get "/donations/:donation_id/lottery-interests" => "lottery_interests#index"

  # Merch packet routes
  get "/merch-packets" => "merch_packets#index"
  put "/merch-packets/:id/ship" => "merch_packets#ship"

  # Notification logs routes
  get "/admin/notification-logs" => "notification_logs#admin_index"
  get "/users/:username/notification-logs" => "notification_logs#user_index"
end

Discourse::Application.routes.draw { mount ::VzekcVerlosung::Engine, at: "vzekc-verlosung" }
