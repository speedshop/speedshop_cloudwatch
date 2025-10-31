Rails.application.routes.draw do
  get "/health", to: "health#index"
  post "/enqueue_jobs", to: "health#enqueue_jobs"
end
