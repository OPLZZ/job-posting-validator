module RDFUtil
  # Collection of utility methods for working with RDF

  # Test if `value` is blank node
  #
  # @params value [String]
  # @returns [Boolean]
  #
  def blank?(value)
    value.start_with? "_:"
  end
end
