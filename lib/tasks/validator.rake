require "fuseki_util"
include FusekiUtil

namespace :validator do
  namespace :data do
    desc "Import background data used for validation"
    task :import_background_data => [:currency_codes, :iso639_1, :schema_org] 
    
    desc "Import currency codes"
    task :currency_codes => :environment do
      paths = ValidatorApp.config["validator"]["files_to_load"]["http://data.damepraci.cz/resource/currency-codes"]
      currencyCodes = RestClient.get paths["remote"].first
      write_data(currencyCodes, paths["local"])
      puts "Currency codes imported"
    end

    desc "Import ISO 639-1 language codes"
    task :iso639_1 => :environment do
      paths = ValidatorApp.config["validator"]["files_to_load"]["http://id.loc.gov/vocabulary/iso639-1"]
      turtle = unzip(RestClient.get paths["remote"].first)
      graph = RDF::Graph.new << RDF::Turtle::Reader.new(turtle)
      
      QUERY = %Q(
        PREFIX mads: <http://www.loc.gov/mads/rdf/v1#>
        PREFIX skos: <http://www.w3.org/2004/02/skos/core#>

        CONSTRUCT {
          ?s skos:notation ?strLang .
        }
        WHERE {
          ?s mads:code ?lang .
          BIND (str(?lang) AS ?strLang)
        }
        GROUP BY ?s ?strLang
      )
      results = SPARQL.execute(QUERY, graph)
      raise "Querying ISO 639-1 codes returned no results" if results.empty?
      iso639_1 = results.dump(:turtle)
      
      write_data(iso639_1, paths["local"])
      puts "Language codes imported"
    end
    
    desc "Import Schema.org + extensions for job market"
    task :schema_org => :environment do
      puts "Importing Schema.org + extensions for job market... it may take a while."
      paths = ValidatorApp.config["validator"]["files_to_load"]["http://vocab.damepraci.eu"]
      graph = RDF::Graph.new
      paths["remote"].each do |url|
        turtle = download url
        graph << RDF::Turtle::Reader.new(turtle)
      end
      schema_org = graph.dump(:turtle)
      write_data(schema_org, paths["local"])
      puts "Schema.org + extensions for job market imported"
    end

    def download(url)
      RestClient.get(url, :headers => {
          # Spoofing user agent string is necessary
          :user_agent => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8)"\
                         "AppleWebKit/534.30 (KHTML, like Gecko) Chrome/12.0.742.112 Safari/ 534.30"
        }
      )
    end

    def unzip(string)
      unzipped = nil
      Zip::Archive.open_buffer(string) do |archive|
        archive.each do |entry|
          unzipped = entry.read
        end
      end
      unzipped
    end

    def write_data(data, filename)
      path = "#{Rails.root}/data/validator/bootstrap/#{filename}"
      File.open(path, "w") { |f| f.write(data) }
    end
  end

  namespace :fuseki do
    desc "Check if the Fuseki server is running"
    task :check_running do
      raise "Fuseki server isn't running" unless server_running? 
    end

    desc "Update Jetty configuration"
    task :configure_jetty => :environment do
      port = ValidatorApp.config["validator"]["port"]
      
      config_path = File.join(Rails.root, "config", "jetty-fuseki.xml")
      config = Nokogiri::XML(File.open(config_path))
      port_element = config.at("Set[@name='port']")
      port_element.content = port
      File.open(config_path, "w") { |file| file.write(config.to_xml) } 
    end

    desc "Initialize Fuseki (start server + load data)"
    task :init => [:start, :load]

    desc "Load background data into the Fuseki RDF store"
    task :load => [:environment, :check_running] do
      puts "Loading background data..."
      fuseki = ValidatorApp.config["validator"]
      data_endpoint = "http://127.0.0.1:#{fuseki["port"]}/#{fuseki["dataset"]}/data"
    
      fuseki["files_to_load"].each do |named_graph, paths|
        load_path = data_path paths["local"]
        raise "File #{load_path} doesn't exist" unless File.exist? load_path

        request_url = "#{data_endpoint}?graph=#{named_graph}"
        response = RestClient::Request.execute(
          :headers  => {
            :content_type => "text/turtle"
          },
          :method   => :put,
          :payload  => File.read(load_path),
          :timeout  => 300,
          :url      => request_url
        )
        raise "Loading file #{load_path} failed. Response status #{response.code}" unless response.code == 201
      end
      puts "Background data loaded"
    end

    desc "Prune Fuseki store"
    task :prune => [:environment, :check_running] do
      fuseki = ValidatorApp.config["validator"]
      endpoint_base = "http://127.0.0.1:#{fuseki["port"]}/#{fuseki["dataset"]}/"
      query_endpoint = endpoint_base + "query"
      update_endpoint = endpoint_base + "update"

      store_size = get_store_size query_endpoint
      if store_size > 100000
        old_graphs = get_old_graphs(query_endpoint, namespace)
        delete_old_graphs(update_endpoint, old_graphs)
        puts "Deleted #{old_graphs.size} old graphs."
      end
    end

    desc "Restart the Fuseki server"
    task :restart => [:stop, :start]

    desc "Start the Fuseki server"
    task :start => :configure_jetty do
      puts "Starting the Fuseki server..."
      raise "Fuseki server already running" if server_running?
      raise "Unable to find fuseki-server" unless system("fuseki-server --version > /dev/null")

      fuseki = ValidatorApp.config["validator"]
      pid = spawn "fuseki-server --memTDB --update --port #{fuseki["port"]} "\
                  "--jetty-config=#{File.join("config", "jetty-fuseki.xml")} "\
                  "/#{fuseki["dataset"]} > /dev/null"
      Process.detach(pid) # Detach the pid
      write_pid pid       # Keep track of the pid
      sleep 10            # Let Fuseki take a deep breath before sending data in
      puts "Fuseki server started on http://localhost:#{fuseki["port"]}" 
    end

    desc "Stop the Fuseki server"
    task :stop => :check_running do
      puts "Stopping the Fuseki server..."

      parent_pid = read_pid
      child_pids = get_child_pids parent_pid
      pids = [parent_pid] + child_pids
      begin
        pids.each { |pid| Process.kill(:SIGTERM, pid) }
        sleep 5 # Wait for some time to free Fuseki port
        File.delete pid_path
        puts "Stopped"
      rescue StandardError => e
        puts "Failed"
        puts e.inspect
      end 
    end
  end
end
