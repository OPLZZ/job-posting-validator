module Helpers
  # Loads fixture from `file_name` in /spec/fixtures directory
  #
  # @param file_name [String]
  # @returns [RDF::Graph, String] `RDF::Graph` for Turtle input, `String` for other file formats
  # @raise [ArgumentError]        Error for non-existent `file_name`
  #
  def load_fixture(file_name)
    file_path = File.join(Rails.root, "spec", "fixtures", file_name)
    raise ArgumentError, "File #{file_path} doesn't exist" unless File.exist? file_path

    if File.extname(file_path) == ".ttl"
      RDF::Graph.load(file_path, format: :ttl)
    else
      File.read file_path
    end
  end
end
