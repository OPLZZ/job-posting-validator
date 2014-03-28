require "spec_helper"

describe ValidatorController do
  describe "GET #index" do
    it "renders the :index view for the request of root URL" do
      get :index
      response.should render_template :index
    end
  end

  describe "POST #validate" do
    context "with invalid input" do
      it "renders the :index view for empty input and flashes an error message" do
        post :validate
        flash[:error].should_not be_nil
        response.should render_template :index 
      end
    end
    
    context "with valid input" do
      it "renders the :preview view for valid input" do
        post :validate, text: load_fixture("minimal_valid_rdfa.html")
        response.should render_template :validate 
      end
    end
  end
end
