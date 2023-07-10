# frozen_string_literal: true

RSpec.describe Boxcars::XNode do
  let(:xml_fragment) do
    '<output>
    <usetool name="resume-reader">
      <params>
       <param name="resume-url">https://www.acme.com/resume.pdf</param>
       <param name="content-type">text/html</param>
      </params>
     </usetool>
    </output>'
  end

  context "with valid xml" do
    it "can get node attribute" do
      expect(described_class.from_xml(xml_fragment).usetool.attributes[:name]).to eq("resume-reader")
    end

    it "can output xml" do
      expect(described_class.from_xml(xml_fragment).xml).to eq(xml_fragment)
    end

    it "can output sub node xml" do
      expect(described_class.from_xml(xml_fragment).usetool.params.param[0].xml).to eq('<param name="resume-url">https://www.acme.com/resume.pdf</param>')
    end

    it "can output sub node text" do
      expect(described_class.from_xml(xml_fragment).usetool.params.param[0].text).to eq("https://www.acme.com/resume.pdf")
    end

    it "can handle multiple sub nodes that are the same" do
      expect(described_class.from_xml(xml_fragment).usetool.params.param.length).to eq(2)
    end
  end

  context "with invalid xml" do
    it "raises an error with no close tag" do
      expect { described_class.from_xml("<output>") }.to raise_error(Boxcars::XmlError, /XML is not valid/)
    end

    it "raises an error with junk" do
      expect { described_class.from_xml("junk") }.to raise_error(Boxcars::XmlError, /XML is not valid/)
    end
  end
end
