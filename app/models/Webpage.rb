require "active_model"
require "open-uri"

class Webpage

  include ActiveModel::Validations

  REJECTED_KEYS = [
    "http://www.w3.org/ns/rdfa#usesVocabulary",
    "http://www.w3.org/ns/md#item"
  ]
  
  attr_accessor :file, :text, :url
  
  # Load RDFa-annotated web page into a model
  #
  # @options arguments [File] :file 
  # @options arguments [String] :text
  # @options arguments [String] :url
  #
  def initialize(options = {})
    @file = options[:file]
    @text = options[:text]
    @url = options[:url]
  end
  
  validate do
    begin
      if !content || content.empty?
        errors[:input] << I18n.translate("errors.input")
      else
        begin
          validation_results = validator.validate data
          unless validation_results.empty?
            errors[:validation] << preprocess_errors(filter_locale(validation_results))
          end 
        rescue SPARQL::Client::MalformedQuery
          errors[:sparql] << I18n.translate("errors.syntax") 
        end
      end
    rescue URI::InvalidURIError => error
      errors[:input] << if error.message.empty?
                          I18n.translate("errors.empty_url")
                        else
                          I18n.translate("errors.invalid_url") + error.message
                        end
    end
  end

  # Reads content from the provided params into a string payload.
  #
  # @returns [String]
  #
  def content
    @content ||= case
                 when @file
                   @file.read
                 when @text
                   @text
                 when @url
                   raise URI::InvalidURIError, @url unless @url =~ URI::regexp
                   response = open(@url)
                   response.read
                 end
  end

  # Loads parsed data from @content
  #
  # @returns [RDF::Graph]
  #
  def data
    @data ||= validator.parse content
  rescue RDF::ReaderError => error
    errors.add(:syntax, error.message)
  end

  # Pre-process RDF graph for rendering its preview
  #
  # @returns [Array<Hash>]
  #
  def job_postings
    @job_postings ||= convert_to_json data 
  end

  # Local alias 
  def validator
    ValidatorApp.instance 
  end

  #
  # @param value [*]
  # @returns [*]
  #
  def choose_locale(value)
    if value.is_a?(Array) && value.any? { |obj| obj.is_a?(Hash) && obj.key?("@language") }
      localised_value = value.select { |obj| obj["@language"] == I18n.locale.to_s }
      localised_value.first["@value"]
    else
      value
    end
  end

  # Filter localizable strings
  #
  # @param errors [Array<Hash>]
  # @returns [Array<Hash>]
  #
  def filter_locale(errors)
    errors.map do |error|
      Hash[error.map { |k, v| [k, choose_locale(v)] }] 
    end
  end

  # Convert `graph` into JSON-LD
  # 
  # @param graph [RDF::Graph] Input RDF graph
  # @returns [Hash]           JSON-LD serialization
  #
  def convert_to_json(graph)
    hash = JSON.parse graph.dump(:jsonld, context: ValidatorApp.jsonld_context[:file].dup)
    hash.key?("@graph") ? nest(hash) : []
  end

  # Replace blank node ID `node` with embedded object from `graph` identified with the `@id`
  #
  # @param node []        Node in the graph. May be String, Array or Hash.
  # @param graph [Hash]   Graph to embed.
  #
  def embed(node, graph)
    case
    when node.is_a?(Array)
      embed_array(node, graph)
    when node.is_a?(Hash)
      embed_hash(node, graph)
    else
      node
    end
  end

  # Multimethods would be nicer...
  # 
  # @param array [Array]
  # @param graph [Hash]
  #
  def embed_array(array, graph)
    if array.all? { |item| item.is_a?(Hash) }
      if array.all? { |item| item.key?("@language") }
        array.map { |item| item["@value"] }.join(", ")
      else
        array.map { |item| embed(item, graph) }
      end
    else
      strings = array.select { |item| item.is_a?(String) }.join(", ")
      others = array.map { |item| embed(item, graph) }
      [strings, others].join(" ")
    end
  end

  # @param hash [Hash]
  # @param graph [Hash]
  #
  def embed_hash(hash, graph)
    case
    when hash.key?("@id") && (hash.size == 1)
      if is_blank?(hash["@id"])
        obj = select_object_by_id(hash["@id"], graph)
        replace_blank_nodes(obj, graph)
      else
        hash["@id"]
      end
    when hash.key?("@language")
      hash["@value"]
    end
  end

  # Remove unwanted properties from a JobPosting instance
  # 
  # @param job_posting [Hash]
  # @returns [Hash]
  #
  def filter_job_posting(job_posting)
    job_posting.reject do |k, v|
      (REJECTED_KEYS.include? k) ||
      ((k == "@id") && v.empty?) 
    end 
  end

  # Test if `value` is blank node
  #
  # @params value [String]
  # @returns [Boolean]
  #
  def is_blank?(value)
    value.start_with? "_:"
  end

  def key_present?(params, key)
    params.key?(key) && ((params[key].respond_to?(:empty?) && !params[key].empty?) || (params[key].size != 0))
  end

  # Nest `hash` (a JSON-LD RDF graph) into tree by replacing blank node
  # references with embedded JSON objects.
  #
  # @param hash [Hash] RDF graph serialized in JSON-LD
  # @return [Array<Hash>]
  #
  def nest(hash)
    graph = hash["@graph"]
    job_postings = select_job_postings graph
    job_postings.map do |job_posting|
      filtered_job_posting = filter_job_posting job_posting
      replace_blank_nodes(filtered_job_posting, graph)
    end
  end

  # Pre-process errors for simpler rendering
  #
  # @param errors [Array]
  # @returns [Array]
  #
  def preprocess_errors(errors)
    errors.map do |error|
      Hash[error.map { |k, v| [k, preprocess_error_value(v)] }]
    end
  end

  def preprocess_error_value(value)
    case
    when value.is_a?(Array)
      value.map { |item| preprocess_error_value(item) }.join(", ")
    when value.is_a?(Hash)
      if id = value["@id"]
        ""
      elsif value.key?("@language")
        value["@value"]
      else
        id
      end
    else
      value
    end
  end

  # Replace blank nodes in `job_posting` with objects from `graph`
  #
  # @param obj [Hash]
  # @param graph [Hash]
  # @returns [Hash]
  #
  def replace_blank_nodes(obj, graph)
    # Remove "@id" attribute of JobPosting instance if it contains blank node
    filtered_obj = obj.select { |k, v| !((k == "@id") && is_blank?(v)) }
    Hash[filtered_obj.map { |k, v| [k, embed(v, graph)] }]
  end

  # Filter instances of JobPosting from `graph`
  #
  # @param graph [Array<Hash>]
  # @returns [Array<Hash>]
  #
  def select_job_postings(graph) 
    graph.select { |obj| obj.key?("@type") && (obj["@type"] == "JobPosting") }
  end

  # Select object using its `id` in the "@id" attribute
  #
  # @param id [String]
  # @param graph [Array<Hash>]
  # @returns [Hash]
  #
  def select_object_by_id(id, graph)
    graph.detect { |obj| obj.key?("@id") && (obj["@id"] == id) }
  end

end
