require "spec_helper"

describe Webpage do
  context "webpage with invalid content" do
    it "is invalid if provided with empty input" do
      webpage = Webpage.new
      webpage.should_not be_valid
      webpage.errors.messages[:input].should_not be_nil
    end

    it "raises an exception if provided with malformed URL" do
      webpage = Webpage.new(url: ("a".."z").to_a.shuffle[0, 8].join)
      expect { webpage.content }.to raise_error(URI::InvalidURIError) 
    end
  end

  context "webpage with valid content" do
    let (:webpage) { Webpage.new(text: load_fixture("minimal_valid_rdfa.html")) }
    let (:empty_graph) { RDF::Graph.new }
    
    it "is valid provided with valid HTML including a JobPosting" do
      webpage.should be_valid
    end

    describe "#convert_to_json" do
    end

    describe "#embed" do
    end

    describe "#embed_array" do
      let(:examples) {[
        [
          [{"@language" => "cs", "@value" => "Jejda!"}, {"@language" => "en", "@value" => "Crikey!"}],
          "Jejda!, Crikey!"
        ],
        [
          ["Jejda!", "Crikey!"],
          "Jejda!, Crikey!"
        ]
      ]}
      it "correctly embeds array data structures" do
        examples.each do |input_data, output_data|
          webpage.embed_array(input_data, empty_graph).should == output_data
        end
      end
    end

    describe "#embed_hash" do
      let(:examples) {[
        [
          {"@language" => "en", "@value" => "Crikey!"},
          "Crikey!"
        ],
        [
          {"@id" => "http://example.com"},
          "http://example.com"
        ],
      ]}
      it "correctly embeds hash data structures" do
        examples.each do |input_data, output_data|
          webpage.embed_hash(input_data, empty_graph).should == output_data
        end
      end
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
