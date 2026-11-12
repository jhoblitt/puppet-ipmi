# frozen_string_literal: true

require 'spec_helper'

# A community given as Sensitive reaches ipmi_snmp unwrapped and still
# sensitive, through the class's snmps hash or a direct declaration, and a
# plain string is sensitive too.
describe 'ipmi' do
  let(:facts) { on_supported_os['redhat-9-x86_64'] }
  let(:params) { { snmps: { 'snmp1' => { 'community' => sensitive('classsecret'), 'lan_channel' => 1 } } } }
  let(:pre_condition) do
    <<~PP
      ipmi_snmp { 'snmp2': community => Sensitive('directsecret'), lan_channel => 2 }
      ipmi_snmp { 'snmp3': community => 'plainsecret', lan_channel => 3 }
    PP
  end

  it { is_expected.to compile.with_all_deps }

  { 'snmp1' => 'classsecret', 'snmp2' => 'directsecret', 'snmp3' => 'plainsecret' }.each do |title, value|
    it "gives #{title} its community unwrapped and sensitive" do
      ral = catalogue.to_ral.resource("Ipmi_snmp[#{title}]")

      expect(ral[:community]).to eq(value)
      expect(ral.parameter(:community).sensitive).to be(true)
    end
  end
end
