require "spec_helper"
require "fuseki_util"

describe FusekiUtil do
  let(:subject_class) { Class.new }
  let(:subject) { subject_class.new }
  let(:config) { ValidatorApp.config }
  let(:data_validator) { ValidatorApp.instance }
  let(:sparql_query_endpoint) { data_validator.sparql }
  let(:sparql_query_endpoint_url) { sparql_query_endpoint.url.to_s }
  let(:sparql_update_endpoint) { data_validator.sparql_update }
  let(:sparql_update_endpoint_url) { sparql_update_endpoint.url.to_s }
  let(:valid_graph) { load_fixture "valid.ttl" }

  before :each do
    subject_class.class_eval { include FusekiUtil }
  end

  describe "#data_path" do
  end
  
  describe "#delete_graphs" do
    it "deletes graph identified by URI" do
      graph_uri = data_validator.load_data valid_graph
      subject.delete_graphs(sparql_update_endpoint_url, [graph_uri])
      query_string = %Q{
        ASK
        WHERE {
          GRAPH <#{graph_uri}> {
            ?s ?p ?o .
          }
        }
      }
      sparql_query_endpoint.query(query_string).should be_false
    end
  end

  context "#fuseki_available?" do
  end

  describe "#get_child_pids" do
  end

  describe "#get_fuseki_command_prefix" do
  end

  describe "#get_old_graphs" do
    it "returns graph inserted seconds ago" do
      delay = 10
      graph_uri = data_validator.load_data valid_graph
      sleep (delay * 1.5)
      old_graphs = subject.get_old_graphs(
        delay.seconds,
        sparql_query_endpoint_url,
        config["namespace"]
      )
      old_graphs.should include(graph_uri)
      sparql_update_endpoint.clear(:graph, graph_uri)
    end
  end

  describe "#get_pid_path" do
  end

  describe "#get_store_size" do
    it "returns correct store size" do
      sparql_update_endpoint.clear :all
      graph_uri = data_validator.load_data valid_graph
      subject.get_store_size(sparql_query_endpoint_url).should == valid_graph.size
    end 
  end

  describe "#pid_path" do
  end

  context "#port_available?" do
  end

  describe "#read_pid" do
  end

  context "#server_running?" do
  end

  describe "#spawn_server" do
  end

  describe "#vendor_fuseki_path" do
  end

  describe "#write_pid" do
  end
end
