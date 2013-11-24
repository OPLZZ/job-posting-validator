require "spec_helper"
require "data_validator"

describe DataValidator do
  let(:valid_args) {
    { 
      base_uri: Faker::Internet.url,
      namespace: Faker::Internet.url,
      sparql_endpoint: Faker::Internet.url,
      sparql_update_endpoint: Faker::Internet.url,
      test_dir: "#{Rails.root}/config/validation-rules"
    }
  }

  context "DataValidator with invalid arguments" do
    it "raises ArgumentError for missing arguments" do
      expect { DataValidator.new }.to raise_error(ArgumentError)
    end
    it "raises ArgumentError for invalid URI in arguments" do
      invalid_args = valid_args.dup
      invalid_args[:base_uri] = "Borken URI"
      expect { DataValidator.new(invalid_args) }.to raise_error(ArgumentError)
    end
    it "raises ArgumentError for invalid path to test directory" do
      invalid_args = valid_args.dup
      invalid_args[:test_dir] = "Borken path"
      expect { DataValidator.new(invalid_args) }.to raise_error(ArgumentError)
    end
  end

  context "DataValidator with valid arguments" do
    let(:data_validator) { DataValidator.new(valid_args) }
    
    it "replaces ?validatedGraph variable with actual graph URI" do
      data_validator.add_graph("?validatedGraph", Faker::Internet.url).should_not include("?validatedGraph")
    end

    it "increases the size of validated graph by 1 by adding the timestamp" do
      data_validator.add_timestamp(
        Faker::Internet.url,
        RDF::Graph.new
      ).size.should equal(RDF::Graph.new.size + 1) 
    end

    it "has access to JSON-LD context which is a Hash" do
      DataValidator::JSONLD_CONTEXT.class.should == Hash
    end

    it "clear graph via SPARQL Update" do
      pending "Shouldn't this be tested rather in sparql-client gem? How to mock SPARQL Update endpoint?"
    end

    it "converts RDF::Graph to JSON-LD" do
      # data_validator.convert_to_json
      pending "Fixtures for both input and output?"
    end

    it "increases the size of data loaded in SPARQL endpoint by the number of triples (+ 1) "\
       "contained in the validated graph when it's loaded" do
      # data_validator.load_data
      pending "Need to run testing SPARQL endpoint, provide fixtures"
    end

    it "correctly parses RDFa embedded in HTML" do
      # data_validator.parse
      pending "Fixtures for both RDFa-annotated page and RDF (in Turtle)?"
    end

    # data_validator.run_test
    # data_validator.validate
  end
end
