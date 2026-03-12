# frozen_string_literal: true

DiscourseSuggestedEdits::Engine.routes.draw do
  get "/suggestions" => "suggestions#index"
  post "/suggestions" => "suggestions#create"
  get "/suggestions/:id" => "suggestions#show"
  put "/suggestions/:id" => "suggestions#update"
  delete "/suggestions/:id" => "suggestions#destroy"
  put "/suggestions/:id/apply" => "suggestions#apply"
  put "/suggestions/:id/dismiss" => "suggestions#dismiss"
end

Discourse::Application.routes.draw { mount DiscourseSuggestedEdits::Engine, at: "/suggested-edits" }
