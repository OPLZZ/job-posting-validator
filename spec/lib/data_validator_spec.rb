require "spec_helper"
require "rake"
require "data_validator"

describe DataValidator do
  let(:valid_args) {
    { 
      base_uri: Faker::Internet.url,
      namespace: Faker::Internet.url,
      sparql_endpoint: Faker::Internet.url,
      sparql_update_endpoint: Faker::Internet.url,
      test_dir: Rails.root.join("config", "validation-rules")
    }
  }
  let(:valid_graph) { load_fixture "valid.ttl" }

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
    let(:data_validator) { ValidatorApp.instance }
   
    it "has access to JSON-LD context which is a Hash" do
      DataValidator::JSONLD_CONTEXT.class.should == Hash
    end

    describe "#add_graph" do
      it "replaces ?validatedGraph variable with actual graph URI" do
        data_validator.add_graph(
          "?validatedGraph", Faker::Internet.url
        ).should_not include("?validatedGraph")
      end
    end
    
    describe "#add_timestamp" do
      it "increases the size of validated graph by 1 by adding the timestamp" do
        data_validator.add_timestamp(
          Faker::Internet.url,
          RDF::Graph.new
        ).size.should equal(1) 
      end
    end

    describe "#convert_to_json" do
      it "converts RDF::Graph to JSON-LD" do
        # Very weak and brittle test, however,
        # other approaches would require fixtures for both input and output,
        # which would make them even more brittle.
        data_validator.convert_to_json(valid_graph).first["@type"].should == "schema:JobPosting"
      end
    end

    describe "#parse" do
      it "correctly parses RDFa embedded in HTML" do
        parsed_graph = data_validator.parse load_fixture("minimal_valid_rdfa.html")
        count_job_postings(parsed_graph).should == count_job_postings(valid_graph)
      end
      it "correctly parses Microdata embedded in HTML" do
        parsed_graph = data_validator.parse load_fixture("minimal_valid_microdata.html")
        count_job_postings(parsed_graph).should == count_job_postings(valid_graph)
      end
    end
    
    context "accessing SPARQL endpoint" do
      describe "#clear_graph" do
        it "clear graph via SPARQL Update" do
          graph_name = data_validator.load_data valid_graph 
          data_validator.clear_graph graph_name
          query = %Q(
            ASK
            WHERE {
              GRAPH <#{graph_name}> { ?s ?p ?o . }
            }
          )
          data_validator.sparql.query(query).should be_false
        end
      end
      
      describe "#load_data" do
        it "increases the size of data loaded in SPARQL endpoint by the number of triples (+ 1) "\
           "contained in the validated graph when it's loaded" do
          sparql_endpoint_url = data_validator.sparql.url.to_s
          old_size = get_store_size sparql_endpoint_url
          data_validator.load_data valid_graph
          get_store_size(sparql_endpoint_url).should == old_size + valid_graph.size
        end
      end
      
      describe "#run_test" do
        # Helper method for running validation rule against valid or invalid fixtures
        #
        # @param test [String]   Name of the validation rule to run
        # @param valid [Boolean] Choose to test against valid or invalid fixtures
        # @returns [Hash]        Validation results in JSON-LD
        #
        def test_rule(rule, valid = true)
          filename = valid ? "valid" : "invalid"
          fixture = load_fixture File.join(File.basename(rule, ".rq"), "#{filename}.ttl")
          graph_name = data_validator.load_data fixture
          test_result = data_validator.run_test(rule, graph_name)
          data_validator.clear_graph graph_name
          test_result
        end

        it "has test data for each validation rule" do
          data_validator.tests.each do |test|
            test_name = File.basename(test, ".rq")
            expected_fixtures = ["valid", "invalid"].map do |filename|
              Rails.root.join("spec", "fixtures", test_name, "#{filename}.ttl").to_s
            end
            fixtures.should include(*expected_fixtures), "Missing fixtures for: #{test}"
          end
        end

        it "produces non-empty validation report for invalid input" do
          data_validator.tests.each do |test|
            test_result = test_rule(test, valid = false)
            test_result.should_not be_empty, "Failed test: #{test}" 
          end
        end

        it "produces empty validation report for valid input" do
          data_validator.tests.each do |test|
            test_result = test_rule(test)
            test_result.should be_empty, "Failed test: #{test}" 
          end
        end
      end

      describe "#validate" do
        it "returns empty array for valid input" do
          data_validator.validate(valid_graph).should be_empty
        end

        it "returns non-empty array for invalid input" do
          data_validator.validate(load_fixture("invalid.ttl")).should_not be_empty
        end
      end
    end
  end
end
