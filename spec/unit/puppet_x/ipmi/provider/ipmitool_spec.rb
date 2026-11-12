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
    # ipmitool's getopt permutes its argv, so without -- an argument that
    # starts with - is taken as one of its own options.
    it 'runs the command after --, with failonfail and combined output' do
      Puppet::Util::Execution.expects(:execute)
                             .with(['/usr/bin/ipmitool', '--', 'lan', 'print', '1'], { failonfail: true, combine: true })
                             .returns('out')

      expect(klass.ipmitool_exec(%w[lan print 1])).to eq('out')
    end

    it 'marks the call sensitive only when asked' do
      Puppet::Util::Execution.expects(:execute)
                             .with(anything, has_entry(sensitive: true))
                             .returns(Puppet::Util::Execution::ProcessOutput.new('', 0))
      klass.ipmitool_exec(['x'], sensitive: true)
    end

    it 'passes the stdin file and failonfail through' do
      Puppet::Util::Execution.expects(:execute)
                             .with(anything, has_entries(stdinfile: '/run/input', failonfail: false))
      klass.ipmitool_exec(['x'], stdinfile: '/run/input', failonfail: false)
    end

    it 'omits sensitive and the stdin file by default' do
      Puppet::Util::Execution.expects(:execute).with { |_cmd, opts| !opts.key?(:sensitive) && !opts.key?(:stdinfile) }
      klass.ipmitool_exec(['x'])
    end

    describe 'when sensitive' do
      def run(output, status, failonfail: true, redact: [])
        result = Puppet::Util::Execution::ProcessOutput.new(output, status)
        Puppet::Util::Execution.expects(:execute).with(anything, has_entries(failonfail: false, sensitive: true)).returns(result)
        klass.ipmitool_exec(%w[exec /run/batch], sensitive: true, redact: redact, failonfail: failonfail)
      end

      def error_for(output, redact: [])
        run(output, 1, redact: redact)
      rescue Puppet::ExecutionFailure => e
        e.message
      end

      it 'raises with the line that echoes the community replaced, however it was echoed' do
        expect(error_for("Setting LAN SNMP Community String to s3cr\nWrite may have failed.\n"))
          .to eq("Execution of '[redacted]' returned 1: Setting LAN SNMP Community String to [redacted]\nWrite may have failed.")
      end

      it 'raises with each value to redact replaced, cut to 16, 18 or 20 bytes too, longest first' do
        pw = 'abcdefghijklmnopqrstuvwxy'
        output = "full #{pw}\n20 #{pw.byteslice(0, 20)}!\n18 #{pw.byteslice(0, 18)}!\n16 #{pw.byteslice(0, 16)}!\n"

        expect(error_for(output, redact: [pw]))
          .to eq("Execution of '[redacted]' returned 1: full [redacted]\n20 [redacted]!\n18 [redacted]!\n16 [redacted]!")
      end

      it 'redacts a value cut inside a multibyte character' do
        value = "#{'a' * 15}éé"
        message = error_for("echo #{value.byteslice(0, 16)}\n".b, redact: [value])

        expect(message).to end_with('echo [redacted]')
        expect(message).to be_valid_encoding
      end

      it 'returns the output when the command succeeds' do
        expect(run('ok', 0).exitstatus).to eq(0)
      end

      it 'returns the output of a failed command when not failing on failure' do
        expect(run('no', 1, failonfail: false).exitstatus).to eq(1)
      end
    end

    it 'leaves the failure of a command that is not sensitive to Puppet' do
      Puppet::Util::Execution.expects(:execute).with(anything, has_entries(failonfail: true)).raises(Puppet::ExecutionFailure, 'lan print failed')

      expect { klass.ipmitool_exec(%w[lan print 1]) }.to raise_error(Puppet::ExecutionFailure, 'lan print failed')
    end
  end

  describe '.exec_token' do
    def line_for(value)
      "lan set 1 snmp #{described_class.exec_token(value, 'an SNMP community')}\n"
    end

    {
      'bare when nothing needs quoting' => 'pub~lic$1\\',
      'double-quoted around a space or single quote' => %(it's mine),
      'single-quoted around a double quote' => %(say "hi" now),
      'quoted and ending in a space' => 'trailing ',
    }.each do |what, value|
      it "writes a value that exec reads back unchanged: #{what}" do
        expect(IpmitoolExecFile.parse(line_for(value))).to eq([['lan', 'set', '1', 'snmp', value]])
      end
    end

    it 'writes a value without whitespace, quotes or # bare' do
      expect(described_class.exec_token('pub~lic', 'x')).to eq('pub~lic')
    end

    {
      'a #' => 'a#b', 'a tab' => "a\tb", 'a newline' => "a\nb", 'a NUL byte' => "a\0b",
      'both quotes' => %(a'b"c), 'a ~ with a space' => 'a ~b', 'a ~ with a quote' => %(a'~),
    }.each do |what, value|
      it "refuses a value containing #{what}, naming what it is but not echoing it" do
        expect { described_class.exec_token(value, 'an SNMP community') }
          .to raise_error(Puppet::Error, %r{\Aipmitool cannot pass an SNMP community containing}) { |e| expect(e.message).not_to include(value) }
      end
    end
  end

  describe '#parse_lan_print' do
    let(:provider) { klass.allocate }

    before { provider.stubs(:lan_channel).returns(2) }

    it 'parses once and caches the result' do
      provider.expects(:ipmitool_exec).with(%w[lan print 2], scrub: true).once.returns("IP Address : 10.0.0.1\n")

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
