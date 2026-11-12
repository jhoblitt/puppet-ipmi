# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/ipmi/provider/ipmitool'

describe PuppetX::Ipmi::Provider::Ipmitool do
  let(:klass) do
    Class.new(described_class) do
      def self.command(_name)
        '/usr/bin/ipmitool'
      end
    end
  end

  describe '.ipmitool_exec' do
    it 'runs the command with failonfail and combined output' do
      Puppet::Util::Execution.expects(:execute)
                             .with(['/usr/bin/ipmitool', 'lan', 'print', '1'], { failonfail: true, combine: true })
                             .returns('out')

      expect(klass.ipmitool_exec(%w[lan print 1])).to eq('out')
    end

    it 'marks the call sensitive only when asked' do
      Puppet::Util::Execution.expects(:execute)
                             .with(anything, has_entry(sensitive: true))
      klass.ipmitool_exec(['x'], sensitive: true)
    end

    it 'passes stdin and failonfail through' do
      Puppet::Util::Execution.expects(:execute)
                             .with(anything, has_entries(stdin: 'data', failonfail: false))
      klass.ipmitool_exec(['x'], stdin: 'data', failonfail: false)
    end

    it 'omits sensitive and stdin by default' do
      Puppet::Util::Execution.expects(:execute).with { |_cmd, opts| !opts.key?(:sensitive) && !opts.key?(:stdin) }
      klass.ipmitool_exec(['x'])
    end
  end

  describe '#parse_lan_print' do
    let(:provider) { klass.allocate }

    before { provider.stubs(:lan_channel).returns(2) }

    it 'parses once and caches the result' do
      provider.expects(:ipmitool_exec).with(%w[lan print 2]).once.returns("IP Address : 10.0.0.1\n")

      2.times { expect(provider.parse_lan_print).to eq('IP Address' => '10.0.0.1') }
    end

    it 're-reads after the cache is invalidated' do
      provider.expects(:ipmitool_exec).twice.returns("IP Address : 10.0.0.1\n")

      provider.parse_lan_print
      provider.invalidate_lan_print_cache!
      provider.parse_lan_print
    end

    it 'tolerates invalidating an empty cache' do
      expect { provider.invalidate_lan_print_cache! }.not_to raise_error
    end
  end
end
