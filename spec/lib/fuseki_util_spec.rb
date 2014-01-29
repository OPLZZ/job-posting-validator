require "spec_helper"
require "fuseki_util"

describe FusekiUtil do
  let (:subject_class) { Class.new }
  let (:subject) { subject_class.new }

  before :each do
    subject_class.class_eval { include FusekiUtil }
  end

  describe "#data_path" do
  end

  describe "#delete_graphs" do
  end

  describe "#fuseki_available?" do
  end

  describe "#get_child_pids" do
  end

  describe "#get_fuseki_command_prefix" do
  end

  describe "#get_old_graphs" do
  end

  describe "#get_pid_path" do
  end

  describe "#get_store_size" do
  end

  describe "#pid_path" do
  end

  describe "#read_pid" do
  end

  describe "#server_running?" do
  end

  describe "#spawn_server" do
  end

  describe "#vendor_fuseki_path" do
  end

  describe "#write_pid" do
  end
end
