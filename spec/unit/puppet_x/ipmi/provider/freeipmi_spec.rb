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
      Puppet::Util::Execution.expects(:execute).with(anything, has_entry(sensitive: true)).returns(Puppet::Util::Execution::ProcessOutput.new('', 0))

      klass.bmcconfig_exec(['x'], sensitive: true)
    end

    describe 'when the output may hold a secret' do
      def error_for(output, **opts)
        result = Puppet::Util::Execution::ProcessOutput.new(output, 1)
        Puppet::Util::Execution.expects(:execute).with(anything, has_entry(failonfail: false)).returns(result)
        klass.bmcconfig_exec(%w[--commit --filename /run/f], **opts)
      rescue Puppet::ExecutionFailure => e
        e.message
      end

      it 'replaces each secret key a checkout prints, commented out or not' do
        output = "Section User4\n\tPassword    s3cret\n\t## Password20   other\n\tUsername  bob\nEndSection\n" \
                 "Section Community_String\n\tCommunity_String   publ1c\nEndSection\n"

        expect(error_for(output, scrub: true)).to eq(
          "Execution of '/usr/sbin/bmcconfig --commit --filename /run/f' returned 1: Section User4\n\tPassword [redacted]\n" \
          "\t## Password20 [redacted]\n\tUsername  bob\nEndSection\nSection Community_String\n\tCommunity_String [redacted]\nEndSection",
        )
      end

      it 'replaces the value ipmi-config validation names for a secret key, however it was quoted' do
        output = "Invalid value 'it's' for key 'Password' in section 'User4'\n" \
                 "Value 'x' for key 'K_g' in section 'Lan_Conf_Security_Keys' cannot be encoded accurately, try another value\n" \
                 "Invalid value 'bogus' for key 'Enable_User' in section 'User4'\n"

        expect(error_for(output, sensitive: true)).to eq(
          "Execution of '[redacted]' returned 1: Invalid value '[redacted]' for key 'Password' in section 'User4'\n" \
          "Value '[redacted]' for key 'K_g' in section 'Lan_Conf_Security_Keys' cannot be encoded accurately, try another value\n" \
          "Invalid value 'bogus' for key 'Enable_User' in section 'User4'",
        )
      end

      it 'redacts each value given, and the lengths it may be cut to' do
        value = 'abcdefghijklmnopqrstuvwxy'

        expect(error_for("#{value}\n#{value[0, 18]}!\n", sensitive: true, redact: [value]))
          .to eq("Execution of '[redacted]' returned 1: [redacted]\n[redacted]!")
      end
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

  describe '.bmc_config_secret' do
    before { Puppet::Util::Execution.expects(:execute).never }

    # Stub bmcconfig_exec, recording each call with the --filename it reads.
    def capture_calls(raises: nil)
      calls = []
      stub = klass.stubs(:bmcconfig_exec).with do |argv, _opts = {}|
        calls << SecretFileCapture.call(argv, argv[argv.index('--filename') + 1])
        true
      end
      raises ? stub.raises(raises) : stub.returns(Puppet::Util::Execution::ProcessOutput.new('', 0))
      calls
    end

    it 'passes the value in a 0600 file that bmc-config reads back unchanged' do
      calls = capture_calls
      klass.bmc_config_secret('--commit', 'User4', 'Password', 'secret', extra_argv: %w[--lan-channel-number 1])

      expect(calls.map(&:argv)).to eq([['--commit', '--filename', calls.first.file, '--lan-channel-number', '1']])
      expect(calls.first.mode).to eq(0o600)
      expect(FreeipmiConfigFile.parse(calls.first.content)).to eq('User4' => { 'Password' => 'secret' })
      expect(File.exist?(calls.first.file)).to be(false)
    end

    it 'removes the file when the command fails' do
      calls = capture_calls(raises: Puppet::ExecutionFailure.new('commit failed'))

      expect { klass.bmc_config_secret('--commit', 'User4', 'Password', 'secret') }.to raise_error(Puppet::ExecutionFailure)
      expect(calls.first.mode).to eq(0o600)
      expect(File.exist?(calls.first.file)).to be(false)
    end

    # A `#` starts a comment only as the first word of a line, and the value
    # always follows its key, so it is carried like any other character.
    ['#leading', 'in#side', 'trailing#', %q(q'u"o\\te), '~;=:$`'].each do |value|
      it "carries #{value.inspect} unchanged" do
        calls = capture_calls
        klass.bmc_config_secret('--diff', 'Community_String', 'Community_String', value)

        expect(FreeipmiConfigFile.parse(calls.first.content)).to eq('Community_String' => { 'Community_String' => value })
      end
    end

    {
      'a space' => 'a b', 'a tab' => "a\tb", 'a newline' => "a\nb", 'a carriage return' => "a\rb",
      'a NUL byte' => "a\0b", 'only a NUL byte' => "\0",
    }.each do |what, value|
      it "refuses a value containing #{what} before running anything, without echoing it" do
        calls = capture_calls

        expect { klass.bmc_config_secret('--commit', 'User4', 'Password', value) }
          .to raise_error(Puppet::Error, %r{\AUser4:Password: freeipmi cannot store a value containing whitespace or a NUL byte\z})
        expect(calls).to be_empty
      end
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
      provider.expects(:bmcconfig_exec).with(['--checkout', '--section', 'Lan_Conf', '--lan-channel-number', '1'], scrub: true).returns(section)

      expect(provider.bmc_config_get('Lan_Conf', 'IP_Address', channel: 1)).to eq('10.0.0.1')
    end

    it 'omits the channel flag when none is given' do
      provider.expects(:bmcconfig_exec).with(['--checkout', '--section', 'Lan_Conf'], scrub: true).returns(section)

      expect(provider.bmc_config_get('Lan_Conf', 'IP_Address')).to eq('10.0.0.1')
    end

    it 'returns nil for a missing key' do
      provider.stubs(:bmcconfig_exec).returns(section)

      expect(provider.bmc_config_get('Lan_Conf', 'Nope', channel: 1)).to be_nil
    end

    it 'skips lines that are not key/value pairs' do
      provider.stubs(:bmcconfig_exec).returns("Section S\n  lonelykey\n  K  v\nEndSection\n")

      expect(provider.send(:section_cache, 'S')).to eq('K' => 'v')
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
