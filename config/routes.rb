# frozen_string_literal: true

VzekcVerlosung::Engine.routes.draw do
  get "/examples" => "examples#index"
  # define routes here
end

Discourse::Application.routes.draw { mount ::VzekcVerlosung::Engine, at: "vzekc-verlosung" }
