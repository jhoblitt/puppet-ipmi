# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_snmp'

describe Puppet::Type.type(:ipmi_snmp).provider(:ipmitool) do
  let(:type) { Puppet::Type.type(:ipmi_snmp) }
  let(:lan_print) do
    File.read('spec/fixtures/unit/puppet/provider/ipmi_network/ipmitool_lan_print.txt')
  end

  before { Puppet::Util::Execution.expects(:execute).never }

  it_behaves_like 'command-confined provider', :ipmitool

  def resource_for(params)
    type.new({ name: 'test', provider: 'ipmitool' }.merge(params))
  end

  describe 'community property' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    # Stub ipmitool_exec, recording each call with the batch file of
    # `ipmitool exec`, read while the command runs.
    def capture_calls(raises: nil)
      calls = []
      stub = provider.stubs(:ipmitool_exec).with do |argv, _opts = {}|
        calls << SecretFileCapture.call(argv, (argv[1] if argv.first == 'exec'))
        true
      end
      raises ? stub.raises(raises) : stub.returns('')
      calls
    end

    it 'returns the current community string' do
      provider.expects(:ipmitool_exec).with(%w[lan print 1], scrub: true).returns(lan_print)

      expect(provider.community).to eq('public')
    end

    it 'sets the community without logging the command or the community ipmitool echoes on failure' do
      provider.expects(:ipmitool_exec).with { |argv, opts = {}| argv.first == 'exec' && opts == { sensitive: true, redact: ['secret'] } }.returns('')

      provider.community = 'secret'
    end

    it 'sets the community through a 0600 exec file, never in argv' do
      calls = capture_calls
      provider.community = 'secret'

      expect(calls.map(&:argv)).to eq([['exec', calls.first.file]])
      expect(calls.first.mode).to eq(0o600)
      expect(IpmitoolExecFile.parse(calls.first.content)).to eq([%w[lan set 1 snmp secret]])
      expect(File.exist?(calls.first.file)).to be(false)
    end

    it 'quotes a community that exec would otherwise split' do
      calls = capture_calls
      provider.community = %(it's mine)

      expect(IpmitoolExecFile.parse(calls.first.content)).to eq([['lan', 'set', '1', 'snmp', %(it's mine)]])
    end

    it 'removes the file when the command fails' do
      calls = capture_calls(raises: Puppet::ExecutionFailure.new('set failed'))

      expect { provider.community = 'secret' }.to raise_error(Puppet::ExecutionFailure)
      expect(calls.first.mode).to eq(0o600)
      expect(File.exist?(calls.first.file)).to be(false)
    end

    it 'refuses a community that ipmitool would take as a request for help, before running anything' do
      calls = capture_calls
      ['help', 'helpdesk', 'help me'].each do |community|
        expect { provider.community = community }.to raise_error(Puppet::Error, %r{starting with "help"})
      end
      expect(calls).to be_empty
    end

    it 'sets a community that only contains help, or starts with it in another case' do
      calls = capture_calls
      provider.community = 'nohelp'
      provider.community = 'Helpdesk'

      expect(calls.map { |c| IpmitoolExecFile.parse(c.content) }).to eq([[%w[lan set 1 snmp nohelp]], [%w[lan set 1 snmp Helpdesk]]])
    end

    it 'refuses a community that exec cannot carry, before running anything, without echoing it' do
      calls = capture_calls
      ['a#b', "a\tb", "a\0b", %(a'b"c), 'a ~b'].each do |community|
        expect { provider.community = community }
          .to raise_error(Puppet::Error, %r{cannot pass an SNMP community}) { |e| expect(e.message).not_to include(community) }
      end
      expect(calls).to be_empty
    end
  end
end
