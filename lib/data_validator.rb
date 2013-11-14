require "digest/sha1"

class DataValidator
  ##
  # Parses RDFa embedded in HTML and runs SPARQL tests on the extracted RDF.
  
  IGNORED_ATTRS = ["@id"]

  JSONLD_CONTEXT = JSON.parse(File.read(
      File.join(Rails.root, "public", "error_context.jsonld")
    ))["@context"] 

  # Create a validator client connected to Fuseki Server
  # 
  # @option arguments [String] :base_uri                Application root URL
  # @option arguments [String] :namespace               URL of the base namespace for newly created graphs
  # @option arguments [String] :sparql_endpoint         URL of the SPARQL query endpoint
  # @option arguments [String] :sparql_update_endpoint  URL of the SPARQL Update endpoint 
  # @option arguments [Boolean] :strict   Flag indicating if string parsing mode should be used.
  #                                       Disabled by default.
  # @option arguments [String] :test_dir  Path to the directory containing SPARQL validation rules.
  #                                       Relative to Rails.root.
  # 
  # @raise  [ArgumentError]
  #
  def initialize(**args)
    required_keys = [
      :base_uri,
      :namespace,
      :sparql_endpoint,
      :sparql_update_endpoint,
      :test_dir
    ]
    required_keys.map do |required_key|
      raise ArgumentError, "Missing keyword argument #{required_key}" unless args.key? required_key
    end

    @base_uri = args[:base_uri].end_with?("/") ? args[:base_uri] : args[:base_uri] + "/"
    @sparql = SPARQL::Client.new args[:sparql_endpoint]
    @sparql_update = SPARQL::Client.new(
                       args[:sparql_update_endpoint],
                       method: :post,
                       protocol: "1.1"
                     )
    @namespace = args[:namespace]
    @tests = Dir[args[:test_dir] + "/*"]
    @strict = args.has_key?(:strict) ? args[:strict] : false
  end  
    
  # Replaces SPARQL query variable `?graphName` with the provided `graph_name` URI
  # to identify, which graph should be queried.
  # 
  # @param query [String]       SPARQL query template
  # @parem graph_name [String]  URL of the validated graph
  # @return [String]
  #
  def add_graph(query, graph_name)
    graph_uri = "<#{graph_name}>"
    query.gsub(/\?validatedGraph/i, graph_uri)
  end

  # Timestamps the provided `graph` identified with `graph_name`
  #
  # @param graph_name [String]  URL of the validated graph
  # @param graph [RDF::Graph]   Validated graph
  # @return [RDF::Graph]
  #
  def add_timestamp(graph_name, graph)
    now = RDF::Literal::DateTime.new DateTime.now.iso8601
    graph << RDF::Statement.new(RDF::URI(graph_name), RDF::DC.issued, now) 
  end

  # Clears the graph identified with `graph_name`
  #
  # @param graph_name [String]  URL of the validated graph
  # @return [undefined] 
  #
  def clear_graph(graph_name)
    @sparql_update.clear(:graph, graph_name)
  end

  # Converts validated `graph` into JSON-LD
  #
  # @param graph [RDF::Graph]  Validated RDF graph
  # @return [Hash] 
  #
  def convert_to_json(graph)
    # Ugly conversion to string and back to JSON,
    # however, other approaches don't respect @context.
    error_hash = JSON.parse graph.dump(:jsonld, context: JSONLD_CONTEXT.dup)
    error_list = error_hash.has_key?("@graph") ? error_hash["@graph"] : [error_hash]
    error_list.map do |item|
      item.delete_if { |key, value| IGNORED_ATTRS.include? key}
      item["@context"] = "#{@base_uri}context.jsonld"
      item 
    end 
  end

  # Loads `data` into a named graph, returns URI of the newly created graph with containing the data
  #
  # @param data [RDF::Graph]                  Parsed RDF data to validate
  # @return [String]                          Automatically generated graph name
  # @raise  [SPARQL::Client::MalformedQuery]  Exception for syntactically invalid data
  #
  def load_data(data)
    sha1 = Digest::SHA1.hexdigest data.dump(:turtle)
    graph_name = RDF::URI.new(@namespace + sha1)
    data = add_timestamp(graph_name, data)

    @sparql_update.insert_data(data, graph: graph_name)
    graph_name
  end

  # Parse HTML `data` with RDFa into RDF graph
  #
  # @param data [String] Input HTML containing RDFa to validate
  # @return [RDF::Graph] RDF graph containing the parsed data
  # @raise [RDF::ReaderError] If instantiated with `:strict` flag, raises `RDF::ReaderError` for syntactically
  #                           malformed input.
  #
  def parse(data)
    graph = RDF::Graph.new
    graph << RDF::RDFa::Reader.new(data, validate: @strict)
    graph 
  end

  # Run a single `test` formalized as SPARQL query on the validated data stored in `graph_name`
  #
  # @param test [String] Name of the file containing the test
  # @param graph_name [String] URI of the validated graph
  # @return [Hash] Validation results serialized in JSON-LD
  #
  def run_test(test, graph_name)
    query = File.read test
    query = add_graph(query, graph_name)
    results = @sparql.query query

    graph = RDF::Graph.new
    graph << results
    
    if graph.empty?
      {}
    else
      convert_to_json graph
    end 
  end

  # Validate input `parsed_data` with SPARQL-based tests
  #
  # @param parsed_data [RDF::Graph] Graph with parsed data that will be validated
  # @return [Array<Hash>]           Validation of results
  #
  def validate(parsed_data)
    graph_name = load_data parsed_data
     
    begin 
      results = @tests.map do |test|
        run_test(test, graph_name)
      end
    ensure
      clear_graph graph_name
    end
      
    # Remove empty results
    results.flatten.reject(&:empty?)
  end
end
