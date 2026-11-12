# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_snmp'

# ipmitool echoes the community it sets ("Setting LAN SNMP Community String
# to ..."), so a failed write must not put its output in the error as is.
# Runs a real catalog against a stand-in `ipmitool` on PATH that fails the
# write the way a BMC that rejects it does.
describe 'ipmi_snmp through the ipmitool provider when the write fails' do
  let(:dir) { Dir.mktmpdir }
  let(:community) { 'Zq9Xk7Wv3Jm2Pb8Rt5' }

  around do |example|
    old = ENV.fetch('PATH', nil)
    ENV['PATH'] = [dir, old].compact.join(File::PATH_SEPARATOR)
    example.run
  ensure
    ENV['PATH'] = old
  end

  after { FileUtils.rm_rf(dir) }

  # @param echo [String] shell expression for the community as echoed
  def fake_ipmitool(echo)
    File.write(File.join(dir, 'ipmitool'), <<~SH)
      #!/bin/sh
      [ "$1" = -- ] && shift
      case "$1" in
        lan) echo 'SNMP Community String   : oldsecret' ;;
        exec)
          read -r _ _ _ _ community < "$2"
          echo "Setting LAN SNMP Community String to #{echo}"
          echo 'LAN Parameter Data does not match!  Write may have failed.'
          exit 1 ;;
      esac
    SH
    File.chmod(0o755, File.join(dir, 'ipmitool'))
  end

  def apply
    Puppet[:statedir] = File.join(dir, 'state')
    catalog = Puppet::Resource::Catalog.new
    catalog.add_resource(Puppet::Type.type(:ipmi_snmp).new(name: 'snmp1', lan_channel: 1, provider: 'ipmitool', community: community))
    catalog.apply.report
  end

  # @return [Array<String>] every run of `min` or more bytes of `value`
  def byteslices(value, min)
    bytes = value.b
    (0..(bytes.bytesize - min)).flat_map { |start| (min..(bytes.bytesize - start)).map { |len| bytes.byteslice(start, len) } }
  end

  {
    'as given' => '$community',
    'cut short' => %($(printf '%.10s' "$community")),
  }.each do |label, echo|
    it "fails the resource without any of the community in the error when ipmitool echoes it #{label}" do
      fake_ipmitool(echo)
      report = apply
      messages = report.logs.map(&:message).join("\n")

      expect(report.resource_statuses['Ipmi_snmp[snmp1]'].failed).to be(true)
      expect(messages).to include("Setting LAN SNMP Community String to [redacted]\n", 'Write may have failed')
      expect(byteslices(community, 4).select { |slice| messages.b.include?(slice) }).to be_empty
      expect(messages).not_to include('oldsecret')
    end
  end

  it 'keeps the current community out of the error when reading it fails' do
    File.write(File.join(dir, 'ipmitool'), <<~SH)
      #!/bin/sh
      echo 'SNMP Community String   : Cu7rrentS3cretVal'
      echo 'Get Channel Info command failed'
      exit 1
    SH
    File.chmod(0o755, File.join(dir, 'ipmitool'))
    report = apply
    messages = report.logs.map(&:message).join("\n")

    expect(report.resource_statuses['Ipmi_snmp[snmp1]'].failed).to be(true)
    expect(messages).to include('SNMP Community String : [redacted]', 'Get Channel Info command failed')
    expect(byteslices('Cu7rrentS3cretVal', 4).select { |slice| messages.b.include?(slice) }).to be_empty
  end
end
