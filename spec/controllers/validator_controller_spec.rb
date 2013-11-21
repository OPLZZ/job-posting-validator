require 'spec_helper'

describe ValidatorController do
  describe "GET #index" do
    it "renders the :index view for the request of root URL" do
      get :index
      response.should render_template :index
    end
  end

  describe "POST #validate" do
    context "with invalid input" do
      it "renders the :index view with error message for empty input" do
        post :validate
        response.should render_template :index 
      end
    end
    
    context "with valid input" do
      it "renders the :preview view for valid input" do
        pending
      end
    end
  end
end
