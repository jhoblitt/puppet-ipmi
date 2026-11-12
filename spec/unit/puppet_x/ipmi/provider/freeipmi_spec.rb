# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/ipmi/provider/freeipmi'

describe PuppetX::Ipmi::Provider::Freeipmi do
  let(:klass) do
    Class.new(described_class) do
      def self.command(name)
        "/usr/sbin/#{name}"
      end
    end
  end

  describe '.config_command' do
    it 'defaults to bmcconfig' do
      expect(described_class.config_command).to eq(:bmcconfig)
    end

    it 'selects the binary a subclass names' do
      pef = Class.new(klass) do
        def self.config_command
          :pefconfig
        end
      end
      Puppet::Util::Execution.expects(:execute).with(['/usr/sbin/pefconfig', '--checkout'], anything)

      pef.bmcconfig_exec(['--checkout'])
    end
  end

  describe '.bmcconfig_exec' do
    it 'runs the command with failonfail and combined output' do
      Puppet::Util::Execution.expects(:execute)
                             .with(['/usr/sbin/bmcconfig', '--checkout'], { failonfail: true, combine: true })
                             .returns('out')

      expect(klass.bmcconfig_exec(['--checkout'])).to eq('out')
    end

    it 'marks the call sensitive only when asked' do
      Puppet::Util::Execution.expects(:execute).with(anything, has_entry(sensitive: true))

      klass.bmcconfig_exec(['x'], sensitive: true)
    end
  end

  describe '.bmc_config_set_argv' do
    it 'builds a commit with a key pair' do
      expect(described_class.bmc_config_set_argv('Lan_Conf', 'IP_Address', '10.0.0.1'))
        .to eq(['--commit', '--key-pair', 'Lan_Conf:IP_Address=10.0.0.1'])
    end

    it 'appends the lan channel when given' do
      expect(described_class.bmc_config_set_argv('Lan_Conf', 'IP_Address', '10.0.0.1', channel: 2))
        .to eq(['--commit', '--key-pair', 'Lan_Conf:IP_Address=10.0.0.1', '--lan-channel-number', '2'])
    end

    it 'refuses a value containing whitespace without echoing it' do
      expect { described_class.bmc_config_set_argv('S', 'K', 'has space') }
        .to raise_error(Puppet::Error, %r{S:K: freeipmi cannot store}) { |e| expect(e.message).not_to include('has space') }
    end
  end

  describe 'instance helpers' do
    let(:provider) { klass.allocate }
    let(:section) do
      <<~OUT
        Section Lan_Conf
                ## Comment line
                IP_Address_Source                  Static
                IP_Address                         10.0.0.1
                Default_Gateway_IP_Address         10.0.0.254
        EndSection
      OUT
    end

    it 'reads a key from a checked-out section' do
      provider.expects(:bmcconfig_exec).with(['--checkout', '--section', 'Lan_Conf', '--lan-channel-number', '1']).returns(section)

      expect(provider.bmc_config_get('Lan_Conf', 'IP_Address', channel: 1)).to eq('10.0.0.1')
    end

    it 'omits the channel flag when none is given' do
      provider.expects(:bmcconfig_exec).with(['--checkout', '--section', 'Lan_Conf']).returns(section)

      expect(provider.bmc_config_get('Lan_Conf', 'IP_Address')).to eq('10.0.0.1')
    end

    it 'returns nil for a missing key' do
      provider.stubs(:bmcconfig_exec).returns(section)

      expect(provider.bmc_config_get('Lan_Conf', 'Nope', channel: 1)).to be_nil
    end

    it 'ignores comments and section markers' do
      provider.stubs(:bmcconfig_exec).returns(section)

      expect(provider.send(:section_cache, 'Lan_Conf', channel: 1).keys)
        .to contain_exactly('IP_Address_Source', 'IP_Address', 'Default_Gateway_IP_Address')
    end

    it 'caches per section and channel' do
      provider.expects(:bmcconfig_exec).twice.returns(section)

      provider.bmc_config_get('Lan_Conf', 'IP_Address', channel: 1)
      provider.bmc_config_get('Lan_Conf', 'IP_Address', channel: 1)
      provider.bmc_config_get('Lan_Conf', 'IP_Address', channel: 2)
    end

    it 're-reads after the cache is invalidated' do
      provider.expects(:bmcconfig_exec).twice.returns(section)

      provider.bmc_config_get('Lan_Conf', 'IP_Address', channel: 1)
      provider.send(:invalidate_section_cache!, 'Lan_Conf', channel: 1)
      provider.bmc_config_get('Lan_Conf', 'IP_Address', channel: 1)
    end

    it 'tolerates invalidating before anything was cached' do
      expect { provider.send(:invalidate_section_cache!, 'Lan_Conf') }.not_to raise_error
    end

    it 'parses empty output as an empty hash' do
      expect([provider.send(:parse_section, nil), provider.send(:parse_section, '')]).to eq([{}, {}])
    end

    it 'writes through the class helper, forwarding sensitive' do
      provider.expects(:bmcconfig_exec)
              .with(['--commit', '--key-pair', 'U:Password=pw', '--lan-channel-number', '1'], sensitive: true)

      provider.bmc_config_set('U', 'Password', 'pw', channel: 1, sensitive: true)
    end
  end
end
