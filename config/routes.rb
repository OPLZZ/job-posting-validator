Validator::Application.routes.draw do
  get "validate", to: "validator#validate" 
  post "validate", to: "validator#validate"

  root to: "validator#index"

  get "about", to: "pages#about"

  # Catch-all template
  match "*path", via: :all, to: "pages#error_404"
end
