# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_snmp'

# ipmi-pef-config prints a value it refuses ("Invalid value '...' for key
# ..."), and a checkout prints the current community, so a failed write or
# read must not put its output in the error as is.  Runs a real catalog
# against a stand-in `ipmi-pef-config` on PATH.
describe 'ipmi_snmp through the freeipmi provider when bmc-config fails' do
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

  def fake_pef_config(body)
    File.write(File.join(dir, 'ipmi-pef-config'), "#!/bin/sh\n#{body}")
    File.chmod(0o755, File.join(dir, 'ipmi-pef-config'))
  end

  def apply
    Puppet[:statedir] = File.join(dir, 'state')
    catalog = Puppet::Resource::Catalog.new
    catalog.add_resource(Puppet::Type.type(:ipmi_snmp).new(name: 'snmp1', lan_channel: 1, provider: 'freeipmi', community: community))
    catalog.apply.report
  end

  # @return [Array<String>] every run of `min` or more bytes of `value`
  def byteslices(value, min)
    bytes = value.b
    (0..(bytes.bytesize - min)).flat_map { |start| (min..(bytes.bytesize - start)).map { |len| bytes.byteslice(start, len) } }
  end

  def leaked(value, messages)
    byteslices(value, 4).select { |slice| messages.b.include?(slice) }
  end

  it 'fails the resource without any of the community in the error when the commit echoes it' do
    fake_pef_config(<<~SH)
      case "$1" in
        --checkout) printf 'Section Community_String\\n\\tCommunity_String  oldsecret\\nEndSection\\n' ;;
        --commit)
          while read -r key value; do [ "$key" = Community_String ] && community=$value; done < "$3"
          echo "Invalid value '$community' for key 'Community_String' in section 'Community_String'"
          echo "Out of Range value '$(printf '%.16s' "$community")' for key 'Community_String' in section 'Community_String'"
          echo "Community_String   $community"
          exit 1 ;;
      esac
    SH
    report = apply
    messages = report.logs.map(&:message).join("\n")

    expect(report.resource_statuses['Ipmi_snmp[snmp1]'].failed).to be(true)
    expect(messages).to include("for key 'Community_String' in section 'Community_String'")
    expect(leaked(community, messages)).to be_empty
    expect(messages).not_to include('oldsecret')
  end

  it 'keeps the current community out of the error when reading it fails' do
    fake_pef_config(<<~SH)
      printf 'Section Community_String\\n\\tCommunity_String  Cu7rrentS3cretVal\\nEndSection\\n'
      echo 'ERROR: Failed to checkout Community_String:Community_String'
      exit 1
    SH
    report = apply
    messages = report.logs.map(&:message).join("\n")

    expect(report.resource_statuses['Ipmi_snmp[snmp1]'].failed).to be(true)
    expect(messages).to include('ERROR: Failed to checkout')
    expect(leaked('Cu7rrentS3cretVal', messages)).to be_empty
  end
end
