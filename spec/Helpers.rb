module Helpers
  # @param file_path [String]
  # @returns [RDF::Graph]
  #
  def load_file(file_path)
    RDF::Graph.load(file_path, format: :ttl)
  end
end
