# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_snmp'

describe Puppet::Type.type(:ipmi_snmp).provider(:freeipmi) do
  let(:type) { Puppet::Type.type(:ipmi_snmp) }
  let(:pef_conf) do
    File.read('spec/fixtures/unit/puppet/provider/ipmi_snmp/pef_config_community.txt')
  end

  before { Puppet::Util::Execution.expects(:execute).never }

  it_behaves_like 'command-confined provider', :pefconfig

  def resource_for(params)
    type.new({ name: 'test', provider: 'freeipmi' }.merge(params))
  end

  describe 'community property' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    # Stub the class's bmcconfig_exec, recording each call with the file
    # its --filename names, read while the command runs.
    def capture_calls(raises: nil)
      calls = []
      stub = described_class.stubs(:bmcconfig_exec).with do |argv, _opts = {}|
        calls << SecretFileCapture.call(argv, argv.include?('--filename') ? argv[argv.index('--filename') + 1] : nil)
        true
      end
      raises ? stub.raises(raises) : stub.returns(Puppet::Util::Execution::ProcessOutput.new('', 0))
      calls
    end

    it 'returns the current community string' do
      provider.expects(:bmcconfig_exec)
              .with(['--checkout', '--section', 'Community_String', '--lan-channel-number', '1'], scrub: true)
              .returns(pef_conf)

      expect(provider.community).to eq('secret')
    end

    it 'sets the community without logging the command' do
      described_class.expects(:bmcconfig_exec).with do |argv, opts = {}|
        argv.values_at(0, 1, 3, 4) == ['--commit', '--filename', '--lan-channel-number', '1'] && opts == { failonfail: true, sensitive: true, redact: ['private'] }
      end

      provider.community = 'private'
    end

    it 'sets the community from a 0600 config file, never in argv' do
      calls = capture_calls
      provider.community = 'pri#vate'

      expect(calls.map(&:argv)).to eq([['--commit', '--filename', calls.first.file, '--lan-channel-number', '1']])
      expect(calls.first.mode).to eq(0o600)
      expect(FreeipmiConfigFile.parse(calls.first.content)).to eq('Community_String' => { 'Community_String' => 'pri#vate' })
      expect(File.exist?(calls.first.file)).to be(false)
    end

    it 'removes the file when the commit fails' do
      calls = capture_calls(raises: Puppet::ExecutionFailure.new('commit failed'))

      expect { provider.community = 'private' }.to raise_error(Puppet::ExecutionFailure)
      expect(calls.first.mode).to eq(0o600)
      expect(File.exist?(calls.first.file)).to be(false)
    end

    it 'refuses a community containing whitespace or a NUL byte, before running anything' do
      calls = capture_calls
      ['my community', "my\0community"].each do |community|
        expect { provider.community = community }
          .to raise_error(Puppet::Error, %r{freeipmi cannot store a value containing whitespace or a NUL byte})
      end
      expect(calls).to be_empty
    end
  end
end
