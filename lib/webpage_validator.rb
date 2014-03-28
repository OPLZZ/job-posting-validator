require "open-uri"
require "rdf_util"

class WebpageValidator < ActiveModel::Validator
  include RDFUtil

  # Initialize with webpage to validate
  #
  # @param webpage [Webpage]
  #
  def initialize(webpage)
    @webpage = webpage
  end

  # Localise value
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

  # Pre-process individual error value
  # 
  # @param value [*]
  #
  def preprocess_error_value(value)
    case
    when value.is_a?(Array)
      value.map { |item| preprocess_error_value(item) }.join(", ")
    when value.is_a?(Hash)
      if id = value["@id"]
        blank?(id) ? "" : id
      elsif value.key?("@language")
        value["@value"]
      end
    else
      value
    end
  end

  def validate
    validate_input 
    validate_content 
  end

  def validate_content
    if !@webpage.content
      @webpage.errors[:input] << I18n.translate("errors.empty_input")
    else
      begin
        validation_results = validator.validate @webpage.data
        unless validation_results.empty?
          preprocessed_errors = preprocess_errors(filter_locale(validation_results))
          @webpage.errors[:validation] = preprocessed_errors
        end 
      rescue RDF::ReaderError => error
        @webpage.errors[:syntax] << error.message
      rescue SPARQL::Client::MalformedQuery
        @webpage.errors[:sparql] << I18n.translate("errors.syntax") 
      end
    end
  rescue URI::InvalidURIError => error
    @webpage.errors[:input] << I18n.translate("errors.invalid_url") + " " + error.message
  rescue OpenURI::HTTPError => error
    @webpage.errors[:input] << I18n.translate("errors.not_found.title") + " " + error.message
  rescue Timeout::Error => error
    @webpage.errors[:input] << I18n.translate("errors.timeout") + " " + error.message
  rescue StandardError => error
    @webpage.errors[:input] << error.message
  end

  def validate_input
    case 
    when @webpage.url
      if @webpage.url.empty?
        @webpage.errors[:input] << I18n.translate("errors.empty_url")
      end
    when @webpage.file
      max_upload_size = ValidatorApp.config["max_upload_size_mb"] || 8
      if @webpage.file.size > max_upload_size.megabytes
        file_size = @webpage.file.size.fdiv(1.megabyte).round(2)
        @webpage.errors[:input] << "File size #{file_size} MB exceeds maximum upload size #{max_upload_size} MB."
      end
    end
  end

  # Local alias 
  def validator
    ValidatorApp.instance 
  end
end
