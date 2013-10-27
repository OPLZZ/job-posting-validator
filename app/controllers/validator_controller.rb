require "open-uri"

class ValidatorController < ApplicationController
  before_filter :set_locale

  def download(input_url)
    raise "Provided URL #{input_url} isn't well-formed." unless input_url =~ URI::regexp
    
    response = open input_url
    response.read
  end

  # Validate and render preview of +payload+
  def preview(payload)
    begin
      parsed_graph = parse payload
    rescue RDF::ReaderError => error
      flash[:error] = error.message
      return redirect_to :action => "index"
    end
    @job_postings = convert_to_json parsed_graph

    begin   
      results = validate parsed_graph
    rescue SPARQL::Client::MalformedQuery
      flash[:error] = I18n.translate("errors.syntax")
      return redirect_to :action => "index"
    end 
    @errors = results[:errors]

    render "preview" 
  end

  # Handle GET requests validating provided +url+
  #
  # For example:
  #   http://localhost:3000/?url=https://dl.dropboxusercontent.com/u/893551/pracovni/OPLZZ_2013/validator-web/data/validator/examples/Filip_Podstavec_3.html
  def validate_get

    data = download params[:url]
    preview data
  end

  # Handle POST requests validating provided +data+ or uploaded +file+
  #
  # For example:
  #   curl --data-urlencode "data@data/validator/examples/Triplethink_4.html" http://localhost:3000/
  def validate_post
    payload = if key_present?(params, :text) 
                params[:text]
              elsif key_present?(params, :file) 
                params[:file].read
              end
    preview payload
  end

  private

  def choose_locale(value)
    if value.is_a?(Array) && value.any? { |obj| obj.respond_to?(:has_key?) && obj.has_key?("@language") }
      localised_value = value.select { |obj| obj["@language"] == I18n.locale.to_s }
      localised_value.first["@value"]
    else
      value
    end
  end

  # Convert +graph+ (instance of RDF::Graph) into JSON-LD (instance of Hash)
  def convert_to_json(graph)
    hash = JSON.parse graph.dump(:jsonld, context: ValidatorApp.jsonld_context[:file].dup)
    hash.key?("@graph") ? nest(hash) : []
  end

  # Replace blank node ID +node+ with embedded object from +graph+ identified with the +id+
  def embed(node, graph)
    if node.is_a? Array
      node.map { |item| embed(item, graph) }
    elsif node.is_a?(Hash) && node.key?("@id") && (node.size == 1)
      if is_blank?(node["@id"])
        obj = select_object_by_id(node["@id"], graph)
        replace_blank_nodes(obj, graph)
      else
        node["@id"]
      end
    else
      node
    end
  end

  # Remove unwanted properties from a JobPosting instance
  def filter_job_posting(job_posting)
    job_posting.reject do |k, v|
      (k == "http://www.w3.org/ns/rdfa#usesVocabulary") ||
      ((k == "@id") && v.empty?) 
    end 
  end

  def filter_locale(errors)
    errors.map do |error|
      Hash[error.map { |k, v| [k, choose_locale(v)] }] 
    end
  end

  # Test if +value+ is blank node
  #
  # For example:
  #   is_blank? "_:b1234" # => true
  #   is_blank? "_:abc"   # => true
  #   is_blank? "abc"     # => false
  def is_blank?(value)
    value.start_with? "_:"
  end

  def key_present?(params, key)
    params.key?(key) && ((params[key].respond_to?(:empty?) && !params[key].empty?) || (params[key].size != 0))
  end

  # Nest +hash+ (a JSON-LD RDF graph) into tree by replacing blank node
  # references with embedded JSON objects.
  def nest(hash)
    graph = hash["@graph"]
    job_postings = select_job_postings graph
    job_postings.map do |job_posting|
      filtered_job_posting = filter_job_posting job_posting
      replace_blank_nodes(filtered_job_posting, graph)
    end
  end

  def parse(data)
    ValidatorApp.instance.parse data
  end

  # Replace blank nodes in +job_posting+ with objects from +graph+
  def replace_blank_nodes(obj, graph)
    # Remove "@id" attribute of JobPosting instance if it contains blank node
    filtered_obj = obj.select { |k, v| !((k == "@id") && is_blank?(v)) }
    Hash[filtered_obj.map { |k, v| [k, embed(v, graph)] }]
  end

  # Filter instances of JobPosting from +graph+
  def select_job_postings(graph) 
    graph.select { |obj| obj.key?("@type") && (obj["@type"] == "JobPosting") }
  end

  # Select object using its +id+ in the "@id" attribute
  def select_object_by_id(id, graph)
    graph.detect { |obj| obj.key?("@id") && (obj["@id"] == id) }
  end

  def set_locale
    I18n.locale = http_accept_language.compatible_language_from(I18n.available_locales)
  end
  
  # Common method for validating pre-processed data
  def validate(parsed_graph)
    results = filter_locale(ValidatorApp.instance.validate parsed_graph)
    { :errors => results }
  end
end
