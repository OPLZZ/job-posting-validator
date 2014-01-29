module FusekiUtil
  # Collection of utility methods for working
  # with Fuseki server

  # Get absolute path to `file` from the directory with bootstrapping data
  #
  # @returns [String] Absolute path to `file`
  #
  def data_path(file)
    Rails.root.join("data", "validator", "bootstrap", file)
  end

  # @param update_endpoint_url [String]   URI of SPARQL Update endpoint
  # @param graphs [Array<String>]         Array of graph URIs to delete
  #
  def delete_graphs(update_endpoint_url, graphs)
    sparql_update = SPARQL::Client.new(update_endpoint_url, :protocol => "1.1")
    graphs.each do |graph|
      sparql_update.clear(:graph, graph)
    end
  end
  
  # Test if there is executable fuseki-server script available on $PATH
  #
  # @returns [Boolean]
  #
  def fuseki_available?(**args)
    prefix = get_fuseki_command_prefix args
    command = "#{prefix}fuseki-server --version > /dev/null 2>&1"
    !!(system command)
  end

  # Source: http://t-a-w.blogspot.com/2010/04/how-to-kill-all-your-children.html
  #
  # @param parent_pid [Fixnum] Parent process' ID
  #
  def get_child_pids(parent_pid)
    descendants = Hash.new{ |ht,k| ht[k] = [k] }
    Hash[*`ps -eo pid,ppid`.scan(/\d+/).map{ |x| x.to_i }].each{ |pid, ppid|
      descendants[ppid] << descendants[pid]
    }
    descendants[parent_pid].flatten - [parent_pid]
  end

  # If it's requested to change path the method prefixes Fuseki commands with
  # cd command.
  #
  # @param args [Hash]
  # @returns [String]
  #
  def get_fuseki_command_prefix(args)
    args[:path] ? "cd #{args[:path]}; #{args[:path]}/" : ""
  end

  # Deletes graphs older than `time` from `namespace` using SPARQL Update `query_endpoint`
  #
  # @param time [Fixnum]            Lower limit of graph age in seconds 
  # @param query_endpoint [String]  URI of SPARQL Update endpoint
  # @param namespace [String]       URI of namespace of the sought graphs
  #
  def get_old_graphs(time, query_endpoint, namespace)
    sparql_query = SPARQL::Client.new query_endpoint
    limit = time.ago.xmlschema
    query = %Q{
      PREFIX dcterms: <http://purl.org/dc/terms/>
      PREFIX xsd:     <http://www.w3.org/2001/XMLSchema#>

      SELECT DISTINCT ?graph
      WHERE {
        GRAPH ?graph {
          ?graph dcterms:issued ?issued .
          FILTER (
            (STRSTARTS(STR(?graph), "#{namespace}"))
            &&
            (?issued < "#{limit}"^^xsd:dateTime)
          )
        }
      }
    }
    response = sparql_query.query query
    response.map do |binding|
      binding[:graph].to_s
    end
  end

  # Returns path to Fuseki process ID,
  # recursively making all missing directories
  #
  # @return [String] Path to Fuseki process ID
  #
  def get_pid_path
    pids_path = File.join("tmp", "pids")
    FileUtils.mkdir_p(pids_path) unless File.directory?(pids_path)
    Rails.root.join(pids_path, "fuseki.pid")
  end

  # Return the number of triples in SPARQL endpoint
  #
  # @param sparql_endpoint [String] URI of SPARQL Query endpoint
  # @returns [Fixnum]               Number of triples in the SPARQL endpoint
  #
  def get_store_size(sparql_endpoint)
    sparql = SPARQL::Client.new sparql_endpoint
    query = %Q{
      SELECT (COUNT(*) AS ?count)
      WHERE {
        GRAPH ?g {
          ?s ?p ?o .
        }
      }
    }
    response = sparql.query query
    response.first[:count].to_i
  end

  # Path to file where Fuseki Server's process ID is stored
  def pid_path
    pid_path ||= get_pid_path
  end

  # Read Fuseki Server's process ID
  #
  # @returns [Fixnum] Fuseki Server's process ID
  #
  def read_pid
    File.read(pid_path).to_i
  end

  # Test whether Fuseki Server is running
  #
  # @returns [Boolean]
  #
  def server_running?
    if File.exist? pid_path
      pid = read_pid
      begin
        Process.kill(0, pid)
      rescue Errno::ESRCH
        return false
      end
    else
      false
    end
  end

  # Spawn Fuseki Server and return its process ID
  #
  # @returns [Fixnum] Fuseki Server's process ID
  #
  def spawn_server(options = {}, **args)
    prefix = get_fuseki_command_prefix args
    command = "#{prefix}fuseki-server --memTDB --update --port #{options["port"]} "\
              "--jetty-config=#{File.join(Rails.root, "config", "jetty-fuseki.xml")} "\
              "/#{options["dataset"]} > /dev/null"
    spawn command
  end

  # Path to local copy of Fuseki Server
  def vendor_fuseki_path
    Dir[File.join(Rails.root, "vendor", "jena-fuseki-*")].first
  end

  # Save Fuseki Server's process ID to a file
  #
  # @param pid [Fixnum] Fuseki Server's process ID
  #
  def write_pid(pid)
    File.open(pid_path, "w") { |f| f.write(pid) }
  end
end
