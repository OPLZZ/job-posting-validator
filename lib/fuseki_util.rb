module FusekiUtil
  # Collection of utility functions for working
  # with Fuseki server

  def data_path(file)
    "#{Rails.root}/data/validator/bootstrap/#{file}"
  end

  def delete_old_graphs(update_endpoint_url, old_graphs)
    sparql_update = SPARQL::Client.new(update_endpoint_url, :protocol => "1.1")
    old_graphs.each do |old_graph|
      sparql_update.clear(:graph, old_graph)
    end
  end
  
  # Test if path is executable fuseki-server script
  def fuseki_available?(**args)
    prefix = get_fuseki_command_prefix args
    command = "#{prefix}fuseki-server --version > /dev/null 2>&1"
    !!(system command)
  end

  # Source: http://t-a-w.blogspot.com/2010/04/how-to-kill-all-your-children.html
  def get_child_pids(parent_pid)
    descendants = Hash.new{ |ht,k| ht[k] = [k] }
    Hash[*`ps -eo pid,ppid`.scan(/\d+/).map{ |x| x.to_i }].each{ |pid, ppid|
      descendants[ppid] << descendants[pid]
    }
    descendants[parent_pid].flatten - [parent_pid]
  end

  def get_old_graphs(query_endpoint, namespace)
    sparql_query = SPARQL::Client.new query_endpoint
    limit = 20.minutes.ago.xmlschema
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

  def get_fuseki_command_prefix(args)
    args.key?(:path) ? "cd #{args[:path]}; #{args[:path]}/" : ""
  end

  # Return the number of triples in the Fuseki store
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

  def pid_path
    "#{Rails.root}/tmp/pids/fuseki.pid"
  end
  
  def read_pid
    File.read(pid_path).to_i
  end

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
  def spawn_server(options = {}, **args)
    prefix = get_fuseki_command_prefix args
    command = "#{prefix}fuseki-server --memTDB --update --port #{options["port"]} "\
              "--jetty-config=#{File.join(Rails.root, "config", "jetty-fuseki.xml")} "\
              "/#{options["dataset"]} > /dev/null"
    spawn command
  end

  def vendor_fuseki_path
    Dir[File.join(Rails.root, "vendor", "jena-fuseki-*")].first
  end

  def write_pid(pid)
    File.open(pid_path, "w") { |f| f.write(pid) }
  end
end
