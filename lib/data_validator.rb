require "digest/sha1"

class DataValidator

  IGNORED_ATTRS = ["@id"]

  JSONLD_CONTEXT = JSON.parse(File.read(
      File.join(Rails.root, "public", "error_context.jsonld")
    ))["@context"] 

  def initialize(**args)
    required_keys = [
      :base_uri,
      :namespace,
      :sparql_endpoint,
      :sparql_update_endpoint,
      :test_dir
    ]
    required_keys.map do |required_key|
      raise "Missing keyword argument #{required_key}" unless args.key? required_key
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
    
  # Replaces SPARQL query variable +?graphName+ with the provided +graph_name+ URI
  # to identify, which graph should be queried. 
  def add_graph(query, graph_name)
    graph_uri = "<#{graph_name}>"
    query.gsub(/\?validatedGraph/i, graph_uri)
  end

  # Timestamps the provided +graph+ identified with +graph_name+
  def add_timestamp(graph_name, graph)
    now = RDF::Literal::DateTime.new DateTime.now.iso8601
    graph << RDF::Statement.new(RDF::URI(graph_name), RDF::DC.issued, now) 
  end

  # Clears the graph identified with +graph_name+
  def clear_graph(graph_name)
    @sparql_update.clear(:graph, graph_name)
  end

  # Converts +graph+ (instance of RDF::Graph) into JSON-LD
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

  # Loads +data+ into a named graph, returns the automatically generated graph name
  def load_data(data)
    sha1 = Digest::SHA1.hexdigest data.dump(:turtle)
    graph_name = RDF::URI.new(@namespace + sha1)
    data = add_timestamp(graph_name, data)

    begin 
      @sparql_update.insert_data(data, graph: graph_name)# TODO: Catch 400 Parse error
      graph_name
    rescue SPARQL::Client::MalformedQuery => error
      abort error.message
    end
  end

  # Parse HTML +data+ with RDFa into RDF graph
  def parse(data)
    graph = RDF::Graph.new
    graph << RDF::RDFa::Reader.new(data, validate: @strict)
    graph 
  end

  # Run a single +test+ formalized as SPARQL query on the validated data stored in +graph_name+
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

  # Validate input +parsed_data+ (instance of RDF::Graph) with SPARQL-based tests
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
