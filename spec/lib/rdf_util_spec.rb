require "spec_helper"
require "rdf_util"

describe RDFUtil do
  let(:subject_class) { Class.new }
  let(:subject) { subject_class.new }

  before :each do
    subject_class.class_eval { include RDFUtil }
  end

  describe "#blank?" do
    let(:examples) {
      {
        "_:b1234" => true,
        "_:abc"   => true,
        "abc"     => false
      }
    }
    it "correctly detects blank nodes" do
      examples.each { |value, result| subject.blank?(value).should == result } 
    end 
  end
end
