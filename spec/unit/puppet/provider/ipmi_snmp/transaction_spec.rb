# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_snmp'

# Runs real catalogs through the real providers, with each provider's exec
# helper answered by an in-memory BMC that records the argv and options of
# every call, and reads the file a write hands its community over in, so
# Puppet's event and log handling of the community take part.
describe 'ipmi_snmp catalog application' do
  let(:bmc) { { community: 'oldsecret' } }
  let(:calls) { [] }
  let(:state_dir) { Dir.mktmpdir }

  before do
    Puppet[:statedir] = state_dir
    Puppet::Util::Execution.expects(:execute).never
  end

  after { FileUtils.rm_rf(state_dir) }

  def apply(backend)
    type = Puppet::Type.type(:ipmi_snmp)
    provider_class = type.provider(backend)
    provider_class.stubs(:suitable?).returns(true)
    resource = type.new(name: 'snmp1', lan_channel: 1, provider: backend, community: 'newsecret')
    exec_helper = { ipmitool: :ipmitool_exec, freeipmi: :bmcconfig_exec }.fetch(backend)
    fake = method(:"fake_#{backend}")
    resource.provider.define_singleton_method(exec_helper) { |argv, **options| fake.call(argv, options) }
    written = Puppet::Util::Execution::ProcessOutput.new('', 0)
    provider_class.stubs(exec_helper).with { |argv, options = {}| fake.call(argv, options) }.returns(written)

    catalog = Puppet::Resource::Catalog.new
    catalog.add_resource(resource)
    catalog.apply.report
  end

  def fake_ipmitool(argv, options)
    calls << [argv, options]
    return "SNMP Community String   : #{bmc[:community]}\n" if argv == %w[lan print 1]

    commands = (argv.first == 'exec') ? IpmitoolExecFile.parse(File.read(argv[1])) : [argv]
    commands.each { |command| bmc[:community] = command.last if command[0..3] == %w[lan set 1 snmp] }
    ''
  end

  def fake_freeipmi(argv, options)
    calls << [argv, options]
    return pef_config_community if argv.first == '--checkout'

    bmc[:community] = if argv.include?('--filename')
                        FreeipmiConfigFile.parse(File.read(argv[argv.index('--filename') + 1])).dig('Community_String', 'Community_String')
                      else
                        argv[2].split('=', 2).last
                      end
    ''
  end

  def pef_config_community
    <<~OUTPUT
      Section Community_String
              Community_String                              #{bmc[:community]}
      EndSection
    OUTPUT
  end

  %i[ipmitool freeipmi].each do |backend|
    context "with the #{backend} provider" do
      it 'changes the community without revealing either value' do
        report = apply(backend)
        events = report.resource_statuses['Ipmi_snmp[snmp1]'].events

        expect(bmc[:community]).to eq('newsecret')
        expect(events.map(&:message)).to eq(['changed [redacted] to [redacted]'])
        expect(events.map { |e| [e.previous_value, e.desired_value] }).to eq([['[redacted]', '[redacted]']])
        expect(report.logs.map(&:message).join("\n")).not_to include('oldsecret', 'newsecret')
      end

      it 'writes once, marked sensitive, and never puts the community in argv' do
        apply(backend)
        writes = calls.reject { |argv, _| argv == %w[lan print 1] || argv.first == '--checkout' }

        expect(writes.size).to eq(1)
        expect(writes.first.last).to include(sensitive: true)
        expect(calls.map(&:first).flatten.grep(%r{secret})).to be_empty
      end
    end
  end
end
