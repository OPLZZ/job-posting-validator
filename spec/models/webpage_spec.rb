require 'spec_helper'

describe Webpage do
  describe "webpage with invalid content" do
    it "is invalid if provided with empty input" do
      webpage = Webpage.new
      webpage.should_not be_valid
    end
  end
end
