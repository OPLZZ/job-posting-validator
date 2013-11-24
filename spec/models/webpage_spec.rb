require 'spec_helper'

describe Webpage do
  context "webpage with invalid content" do
    it "is invalid if provided with empty input" do
      webpage = Webpage.new
      webpage.should_not be_valid
      webpage.errors.messages[:input].should_not be_nil
    end
  end

  context "webpage with valid content" do
    it "is valid provided with valid HTML including a JobPosting" do
      webpage = Webpage.new(text: load_fixture("minimal_valid_webpage.html"))
      webpage.should be_valid
    end
  end
end
