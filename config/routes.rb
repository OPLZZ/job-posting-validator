Validator::Application.routes.draw do
  get "validate", to: "validator#validate" 
  post "validate", to: "validator#validate"

  root to: "validator#index" 
end
