require "data_validator"
require "fileutils"
require "fuseki_util"
require "open-uri"
include FusekiUtil

namespace :validator do
  # Load configuration of the application
  task :load_config do
    @config = YAML.load_file(File.join(Rails.root, "config", "config.yml"))[Rails.env]
  end

  namespace :data do
    desc "Import background data used for validation"
    task :import_background_data => [:currency_codes, :iso639_1, :schema_org] 
    
    # Import currency codes
    task :currency_codes => "rake:validator:load_config" do
      paths = @config["files_to_load"]["http://data.damepraci.cz/resource/currency-codes"]
      currencyCodes = RestClient.get paths["remote"].first
      write_data(currencyCodes, paths["local"])
      puts "Currency codes imported"
    end

    # Import ISO 639-1 language codes
    task :iso639_1 => "rake:validator:load_config" do
      paths = @config["files_to_load"]["http://id.loc.gov/vocabulary/iso639-1"]
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
    
    # Import Schema.org + extensions for job market
    task :schema_org => "rake:validator:load_config" do
      puts "Importing Schema.org + extensions for job market... it may take a while."
      paths = @config["files_to_load"]["http://vocab.damepraci.eu"]
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
      path = File.join(Rails.root, "data", "validator", "bootstrap", filename)
      File.open(path, "w") { |f| f.write(data) }
    end
  end

  namespace :fuseki do
    # Check if the Fuseki server is running
    task :check_running do
      raise "Fuseki server isn't running" unless server_running? 
    end

    # Update Jetty configuration
    task :configure_jetty => "rake:validator:load_config" do
      port = @config["port"]
      
      config_path = File.join(Rails.root, "config", "jetty-fuseki.xml")
      config = Nokogiri::XML(File.open(config_path))
      port_element = config.at("Set[@name='port']")
      port_element.content = port
      File.open(config_path, "w") { |file| file.write(config.to_xml) } 
    end

    # Download the Fuseki Server
    task :download do
      puts "Downloading Fuseki Server"
      version_number = ENV["FUSEKI_VERSION"] || "1.0.1" 
      url = "http://www.apache.org/dist/jena/binaries/jena-fuseki-#{version_number}-distribution.zip"
        
      begin
        progress_bar = nil
        @response = open(url,
                         content_length_proc: lambda { |total|
                           progress_bar = ProgressBar.create(title: "Downloading", total: total)
                         },
                         progress_proc: lambda { |size|
                           if progress_bar && progress_bar.progress < (progress_bar.total - size)
                             progress_bar.progress += size
                           end 
                         })
      rescue OpenURI::HTTPError => e
        puts e.message
        exit
      end
    end

    desc "Initialize Fuseki (start server + load data)"
    task :init => [:start, :load]

    desc "Download and install Fuseki server. Specify the desired Fuseki version number "\
         "as $FUSEKI_VERSION environment variable (default is 1.0.0)."
    task :install => [:download, :unzip] do
      # Make fuseki-server executable
      File.chmod(0755, File.join(vendor_fuseki_path, "fuseki-server")) 
      puts "Fuseki Server installed"
    end

    # Load background data into the Fuseki RDF store
    task :load => ["rake:validator:load_config", :check_running] do
      puts "Loading background data..."
      data_endpoint = "http://127.0.0.1:#{@config["port"]}/#{@config["dataset"]}/data"
    
      @config["files_to_load"].each do |named_graph, paths|
        load_path = data_path paths["local"]
        raise "File #{load_path} doesn't exist" unless File.exist? load_path

        request_url = "#{data_endpoint}?graph=#{named_graph}"
        response = RestClient::Request.execute(
          headers: {
            content_type: "text/turtle"
          },
          method:  :put,
          payload: File.read(load_path),
          timeout: 300,
          url:     request_url
        )
        raise "Loading file #{load_path} failed. Response status #{response.code}" unless response.code == 201
      end
      puts "Background data loaded"
    end

    desc "Prune Fuseki store"
    task :prune => ["rake:validator:load_config", :check_running] do
      endpoint_base = "http://127.0.0.1:#{@config["port"]}/#{@config["dataset"]}/"
      query_endpoint = endpoint_base + "query"
      update_endpoint = endpoint_base + "update"

      store_size = get_store_size query_endpoint
      if store_size > 100000
        old_graphs = get_old_graphs(20.minutes, query_endpoint, namespace)
        delete_graphs(update_endpoint, old_graphs)
        puts "Deleted #{old_graphs.size} old graphs."
      end
    end

    desc "Restart the Fuseki server"
    task :restart => [:stop, :start]

    desc "Start the Fuseki server"
    task :start => :configure_jetty do
      puts "Starting the Fuseki server..."
      raise "Fuseki server already running" if server_running?

      if fuseki_available? 
        pid = spawn_server @config
      elsif fuseki_available? path: vendor_fuseki_path
        pid = spawn_server(@config, path: vendor_fuseki_path)
      else
        raise "Unable to find fuseki-server. Install it "\
              "by using: rake validator:fuseki:install" 
      end
      
      Process.detach pid  # Detach the process ID
      write_pid pid       # Keep track of the process ID
      sleep 10            # Let Fuseki take a deep breath before sending data in
      puts "Fuseki server started on http://localhost:#{@config["port"]}" 
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

    desc "Test SPARQL rule (provided as task argument) with corresponding fixture"
    task :test_rule, [:rule_name] => ["rake:validator:load_config", :check_running] do |_, args|
      raise "Provide file name of the SPARQL test to run by using "\
            "rake validator:fuseki:test_rule[rule file name]" unless args[:rule_name]
      rule_path = File.join(Rails.root, "config", "validation-rules", args[:rule_name])
      raise "File #{rule_path} doesn't exist." unless File.exist? rule_path
      rule_test = RDF::Graph.load(
        File.join(Rails.root, "spec", "fixtures", File.basename(args[:rule_name], ".rq") + ".ttl"),
        format: :ttl
      )

      base_url = "http://127.0.0.1:#{@config["port"]}/#{@config["dataset"]}/"
      endpoint_url = base_url + "sparql"
      validator = DataValidator.new(
        base_uri:               @config["base_uri"],
        namespace:              @config["namespace"],
        sparql_endpoint:        endpoint_url,
        sparql_update_endpoint: "#{base_url}update",
        test_dir:               File.join(Rails.root, "config", "validation-rules")
      )

      puts "Running test #{args[:rule_name]} on SPARQL endpoint #{endpoint_url}."
      
      graph_name = validator.load_data rule_test
      results = validator.run_test(rule_path, graph_name)
      validator.clear_graph graph_name

      puts JSON.pretty_generate results
    end

    # Unzip the downloaded Fuseki Server distribution
    task :unzip => :download do
      Zip::Archive.open(@response.path) do |archive|
        archive.each do |entry|
          path = File.join("vendor", entry.name)
          FileUtils.mkdir_p(File.dirname(path))
          if entry.directory?
            FileUtils.mkdir_p(path)
          else
            File.open(path, "wb") { |f| f << entry.read }
          end
        end
      end
      puts "Fuseki Server unzipped"
    end
  end
end
