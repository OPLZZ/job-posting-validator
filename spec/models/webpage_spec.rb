require "spec_helper"

describe Webpage do
  context "webpage with invalid content" do
    it "is invalid if provided with empty input" do
      webpage = Webpage.new
      webpage.should_not be_valid
      webpage.errors.messages[:input].should_not be_nil
    end
  end

  context "webpage with valid content" do
    let (:webpage) { Webpage.new(text: load_fixture("minimal_valid_rdfa.html")) }
    
    it "is valid provided with valid HTML including a JobPosting" do
      webpage.should be_valid
    end

    describe "#convert_to_json" do
    end

    describe "#embed" do
    end

    describe "#embed_array" do
    end

    describe "#embed_hash" do
    end

    describe "#filter_job_posting" do
    end

    describe "#key_present?" do
    end

    describe "#nest" do
    end

    describe "#replace_blank_nodes" do
    end

    describe "#select_job_postings" do
    end

    describe "#select_object_by_id" do
    end
  end
end
