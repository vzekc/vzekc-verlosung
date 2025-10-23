# frozen_string_literal: true

VzekcVerlosung::Engine.routes.draw do
  get "/examples" => "examples#index"
  post "/lotteries" => "lotteries#create"

  post "/tickets" => "tickets#create"
  delete "/tickets/:post_id" => "tickets#destroy"
  get "/tickets/status/:post_id" => "tickets#status"
end

Discourse::Application.routes.draw { mount ::VzekcVerlosung::Engine, at: "vzekc-verlosung" }
