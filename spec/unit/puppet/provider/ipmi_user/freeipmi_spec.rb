# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_user'

describe Puppet::Type.type(:ipmi_user).provider(:freeipmi) do
  let(:fixtures) { 'spec/fixtures/unit/puppet/provider/ipmi_user' }
  let(:asus_checkout) { File.read("#{fixtures}/bmc_config_checkout_asus.txt") }
  let(:supermicro_checkout) { File.read("#{fixtures}/bmc_config_checkout_supermicro.txt") }

  before do
    described_class.stubs(:suitable?).returns(true)
    Puppet::Util::Execution.expects(:execute).never
  end

  it_behaves_like 'command-confined provider', :bmcconfig

  def result(output, status = 0)
    Puppet::Util::Execution::ProcessOutput.new(output, status)
  end

  it 'includes the shared user logic' do
    expect(described_class.ancestors).to include(PuppetX::Ipmi::Provider::UserLogic)
  end

  describe '.parse_checkout' do
    let(:users) { described_class.parse_checkout(supermicro_checkout) }

    it 'returns one entry per User section, sorted by id' do
      expect(users.map { |u| u[:id] }).to eq(users.map { |u| u[:id] }.sort)
      expect(users.first[:id]).to eq(1)
    end

    it 'parses name, privilege and enabled state' do
      admin = users.find { |u| u[:id] == 2 }

      expect(admin).to eq(id: 2, name: 'ADMIN', priv: 4, status: :enabled)
    end

    it 'reports unset slots as empty and disabled, with a privilege of none' do
      expect(users.find { |u| u[:id] == 3 }).to eq(id: 3, name: '', priv: 0, status: :disabled)
    end

    it 'treats <username-not-set-yet> as empty, and a missing Enable_User as unknown' do
      output = "Section User2\n        Username                                      <username-not-set-yet>\nEndSection\n"

      expect(described_class.parse_checkout(output)).to eq([{ id: 2, name: '', priv: 0, status: :unknown }])
    end

    it 'reads OEM_Proprietary as 5, and a privilege it does not know as nil' do
      output = "Section User2\n Lan_Privilege_Limit OEM_Proprietary\nEndSection\nSection User3\n Lan_Privilege_Limit Bogus\nEndSection\n"

      expect(described_class.parse_checkout(output).map { |u| u[:priv] }).to eq([5, nil])
    end

    it 'returns an empty list for empty output' do
      expect(described_class.parse_checkout('')).to eq([])
    end
  end

  describe '.lan_channels' do
    def probe(output, status = 0)
      described_class.expects(:bmcconfig_exec).with(%w[--checkout --verbose --verbose --section User1], failonfail: false).returns(result(output, status))
    end

    # --verbose adds the Serial_ keys, which a BMC with no serial channel
    # cannot read.
    let(:serial_unread) { "\t## Unable to checkout User1:Serial_Enable_IPMI_Msgs\n\t## Unable to checkout User1:Serial_Privilege_Limit : Not Supported\n" }

    it 'reads the channel of every per-channel key of a verbose checkout, despite unreadable serial keys' do
      probe("Section User1\n\t## Username NULL\n\tLan_Privilege_Limit_Channel_1 No_Access\n" \
            "\t## Lan_Privilege_Limit_Channel_8 <username-not-set-yet>\n\tLan_Session_Limit_Channel_3 0\n#{serial_unread}EndSection\n", 1)

      expect(described_class.lan_channels).to eq([1, 8])
    end

    it 'finds none when the BMC has one LAN channel, whose keys carry no channel' do
      probe("Section User1\n\tLan_Privilege_Limit No_Access\n#{serial_unread}EndSection\n", 1)

      expect(described_class.lan_channels).to eq([])
    end

    it 'fails, rather than find one LAN channel, when the checkout fails' do
      ["ipmi_ctx_open_outofband_2_0: connection timeout\n", "Section User1\n\tLan_Privilege_Limit No_Access\n"].each do |output|
        probe(output, 1)

        expect { described_class.lan_channels }.to raise_error(Puppet::Error, %r{bmc-config --checkout --section User1 failed \(exit 1\)})
      end
      probe("Section User1\n\tLan_Privilege_Limit No_Access\nEndSection\n", 2)

      expect { described_class.lan_channels }.to raise_error(Puppet::Error, %r{\(exit 2\)})
    end

    it 'fails, rather than miss the channel, when a LAN key could not be read' do
      probe("Section User1\n\tLan_Privilege_Limit_Channel_1 No_Access\n\t## Unable to checkout User1:Lan_Privilege_Limit_Channel_2\n#{serial_unread}EndSection\n", 1)

      expect { described_class.lan_channels }.to raise_error(Puppet::Error, %r{could not read User1:Lan_Privilege_Limit_Channel_2\z})
    end
  end

  describe '.read_table' do
    it 'checks out every channel, taking the name and Enable_User from the first' do
      ch2 = supermicro_checkout.sub(%r{(Section User2.*?Lan_Privilege_Limit\s+)Administrator}m, '\1No_Access')
                               .sub(%r{(Section User2.*?Enable_User\s+)Yes}m, '\1No')
      described_class.expects(:bmcconfig_exec).with(%w[--checkout --lan-channel-number 1], failonfail: false).returns(result(supermicro_checkout))
      described_class.expects(:bmcconfig_exec).with(%w[--checkout --lan-channel-number 2], failonfail: false).returns(result(ch2))

      admin = described_class.read_table([1, 2]).find { |u| u[:id] == 2 }

      expect(admin).to eq(id: 2, name: 'ADMIN', status: :enabled, privs: { 1 => 4, 2 => 15 })
    end
  end

  describe '.read_users' do
    it 'checks out the whole configuration for the channel' do
      described_class.expects(:bmcconfig_exec).with(%w[--checkout --lan-channel-number 2], failonfail: false).returns(result(supermicro_checkout))

      expect(described_class.read_users(2).map { |u| u[:id] }).to include(2, 4)
    end

    it 'accepts exit status 1 when the output contains user sections' do
      described_class.expects(:bmcconfig_exec).returns(result(supermicro_checkout, 1))

      expect(described_class.read_users(1)).not_to be_empty
    end

    it 'raises when the checkout fails without user sections' do
      described_class.expects(:bmcconfig_exec).returns(result('permission denied', 1))

      expect { described_class.read_users(1) }.to raise_error(Puppet::Error, %r{bmc-config --checkout failed \(exit 1\)})
    end

    it 'rejects a checkout whose user sections are not contiguous' do
      # Drop the User4 section, leaving a gap: a truncated checkout that a
      # naive "any User section" check would accept as complete.
      gapped = supermicro_checkout.sub(%r{^Section User4$.*?^EndSection$}m, '')
      described_class.expects(:bmcconfig_exec).returns(result(gapped, 1))

      expect { described_class.read_users(1) }.to raise_error(Puppet::Error, %r{bmc-config --checkout failed \(exit 1\)})
    end

    it 'rejects a checkout truncated before its final EndSection' do
      truncated = supermicro_checkout.lines.reject { |l| l.strip == 'EndSection' }.join
      described_class.expects(:bmcconfig_exec).returns(result(truncated, 1))

      expect { described_class.read_users(1) }.to raise_error(Puppet::Error, %r{bmc-config --checkout failed \(exit 1\)})
    end
  end

  describe 'writes' do
    it 'sets a name' do
      described_class.expects(:bmc_config_set).with('User4', 'Username', 'bob', channel: 1)
      described_class.write_name(1, 4, 'bob')
    end

    describe 'a password' do
      it 'is committed from a 0600 config file, never in argv' do
        pw = %(p#ss~w"'rd)
        calls = capture_calls
        described_class.write_password(1, 4, pw)

        expect(calls.map(&:argv)).to eq([['--commit', '--filename', calls.first.file, '--lan-channel-number', '1']])
        expect(calls.first).to have_attributes(mode: 0o600, content: "Section User4\n\tPassword\t#{pw}\nEndSection\n")
        expect(File.exist?(calls.first.file)).to be(false)
      end

      # bmc-config's Password key takes up to 20 bytes, storing more than 16
      # in the 20-byte form; Password20 is only its legacy alias.
      it 'of 17 to 20 bytes is committed and diffed through the Password key' do
        pw = 'Q7wP2mK9vX4nB8cL5tR1'
        calls = capture_calls
        described_class.write_password(1, 4, pw)
        described_class.password_matches?(1, 4, pw)

        expect(calls.map(&:content)).to eq(["Section User4\n\tPassword\t#{pw}\nEndSection\n"] * 2)
      end

      it 'longer than 20 bytes, which bmc-config refuses, is refused without running anything or echoing it' do
        calls = capture_calls
        pw = 'a' * 21

        expect { described_class.write_password(1, 4, pw) }.to raise_error(Puppet::Error, %r{longer than 20 bytes}) { |e| expect(e.message).not_to include(pw) }
        expect(calls).to be_empty
      end

      it 'containing whitespace is refused without running anything or echoing it' do
        calls = capture_calls

        expect { described_class.write_password(1, 4, 'has space') }.to raise_error(Puppet::Error) { |e| expect(e.message).not_to include('has space') }
        expect(calls).to be_empty
      end

      it 'containing a NUL byte is refused without running anything' do
        calls = capture_calls

        expect { described_class.write_password(1, 4, "se\0cret") }.to raise_error(Puppet::Error, %r{NUL byte})
        expect(calls).to be_empty
      end

      it 'file is removed when the commit fails' do
        calls = capture_calls(raises: Puppet::ExecutionFailure.new('commit failed'))

        expect { described_class.write_password(1, 4, 'secret') }.to raise_error(Puppet::ExecutionFailure)
        expect(calls.first.mode).to eq(0o600)
        expect(File.exist?(calls.first.file)).to be(false)
      end
    end

    it 'sets the privilege limit by name' do
      described_class.expects(:bmc_config_set).with('User4', 'Lan_Privilege_Limit', 'Operator', channel: 1)
      described_class.write_priv(1, 4, 3)
    end

    describe 'enabling' do
      let(:seq) { sequence('enable') }

      def expect_set(key, value)
        described_class.expects(:bmc_config_set).with('User4', key, value, channel: 1).in_sequence(seq)
      end

      it 'writes the privilege before and after enabling the user, then SOL and channel access' do
        [
          %w[Lan_Privilege_Limit Administrator], %w[Enable_User Yes], %w[Lan_Privilege_Limit Administrator],
          %w[SOL_Payload_Access Yes], %w[Lan_Enable_IPMI_Msgs Yes], %w[Lan_Enable_Link_Auth Yes],
        ].each { |key, value| expect_set(key, value) }

        described_class.grant_access(1, 4, 4)
      end

      it 'tolerates a privilege write refused while the user is disabled' do
        expect_set('Lan_Privilege_Limit', 'Administrator').raises(Puppet::ExecutionFailure, 'refused')
        [
          %w[Enable_User Yes], %w[Lan_Privilege_Limit Administrator], %w[SOL_Payload_Access Yes],
          %w[Lan_Enable_IPMI_Msgs Yes], %w[Lan_Enable_Link_Auth Yes],
        ].each { |key, value| expect_set(key, value) }

        expect { described_class.grant_access(1, 4, 4) }.not_to raise_error
      end

      it 'disables the user again and re-raises when a write after enabling fails' do
        expect_set('Lan_Privilege_Limit', 'Administrator')
        expect_set('Enable_User', 'Yes')
        expect_set('Lan_Privilege_Limit', 'Administrator').raises(Puppet::ExecutionFailure, 'priv failed')
        expect_set('Enable_User', 'No')

        expect { described_class.grant_access(1, 4, 4) }.to raise_error(Puppet::ExecutionFailure, 'priv failed')
      end
    end

    describe 'disabling' do
      # Expect the revoke writes and Enable_User No in sequence; each key
      # in `raising` raises its error.
      def expect_disable(raising = {})
        seq = sequence('disable')
        [
          %w[Lan_Privilege_Limit No_Access], %w[Lan_Enable_IPMI_Msgs No], %w[Lan_Enable_Link_Auth No],
          %w[SOL_Payload_Access No], %w[Enable_User No],
        ].each do |key, value|
          write = described_class.expects(:bmc_config_set).with('User4', key, value, channel: 1).in_sequence(seq)
          write.raises(raising[key]) if raising.key?(key)
        end
      end

      it 'revokes privilege, channel and SOL access before disabling' do
        expect_disable
        described_class.revoke_access([1], 4)
      end

      it 'revokes every channel given, then disables the user once' do
        seq = sequence('disable')
        [1, 2].each do |c|
          [%w[Lan_Privilege_Limit No_Access], %w[Lan_Enable_IPMI_Msgs No], %w[Lan_Enable_Link_Auth No], %w[SOL_Payload_Access No]].each do |key, value|
            described_class.expects(:bmc_config_set).with('User4', key, value, channel: c).in_sequence(seq)
          end
        end
        described_class.expects(:bmc_config_set).with('User4', 'Enable_User', 'No', channel: 1).in_sequence(seq)

        described_class.revoke_access([1, 2], 4)
      end

      it 'still revokes the rest and disables the user, then re-raises, when a revoke write fails' do
        expect_disable('Lan_Privilege_Limit' => Puppet::ExecutionFailure.new('priv failed'))

        expect { described_class.revoke_access([1], 4) }.to raise_error(Puppet::ExecutionFailure, 'priv failed')
      end

      it 'tolerates permission changes that an already disabled user refuses' do
        expect_disable('Lan_Privilege_Limit' => Puppet::ExecutionFailure.new('refused'), 'SOL_Payload_Access' => Puppet::ExecutionFailure.new('refused'))

        expect { described_class.revoke_access([1], 4, already_disabled: true) }.not_to raise_error
      end

      it 'fails when an already disabled user cannot be disabled' do
        expect_disable('Enable_User' => Puppet::ExecutionFailure.new('disable failed'))

        expect { described_class.revoke_access([1], 4, already_disabled: true) }.to raise_error(Puppet::ExecutionFailure, 'disable failed')
      end
    end

    describe 'checking values before any write' do
      it 'accepts what the writers can carry' do
        expect { described_class.check_name(1, 4, 'bob') }.not_to raise_error
        expect { described_class.check_password(1, 4, %(p#ss~w"'rd)) }.not_to raise_error
        expect { described_class.check_password(1, 4, 'Q7wP2mK9vX4nB8cL5tR1') }.not_to raise_error
      end

      it 'refuses a username with whitespace or a NUL byte, without echoing it' do
        ['b b', "b\0b"].each do |name|
          expect { described_class.check_name(1, 4, name) }.to raise_error(Puppet::Error) { |e| expect(e.message).not_to include(name) }
        end
      end

      it 'refuses the passwords write_password refuses, without echoing them' do
        ['has space', "se\0cret", 'a' * 21].each do |pw|
          expect { described_class.check_password(1, 4, pw) }.to raise_error(Puppet::Error) { |e| expect(e.message).not_to include(pw) }
        end
      end
    end

    it 'raises when a value contains whitespace, without echoing it' do
      expect { described_class.bmc_config_set('User4', 'Password', 'has space', channel: 1, sensitive: true) }
        .to raise_error(Puppet::Error) { |e| expect(e.message).not_to include('has space') }
    end
  end

  describe '.password_matches?' do
    it 'diffs against a 0600 config file, never in argv, and is true without a mismatch' do
      calls = capture_calls

      expect(described_class.password_matches?(1, 4, 'secret')).to be(true)
      expect(calls.map(&:argv)).to eq([['--diff', '--filename', calls.first.file]])
      expect(calls.first).to have_attributes(mode: 0o600, content: "Section User4\n\tPassword\tsecret\nEndSection\n")
      expect(File.exist?(calls.first.file)).to be(false)
    end

    it 'is false when --diff reports a mismatch' do
      capture_calls(output: "User4:Password - input=`secret':actual=`<something else>'\n")
      expect(described_class.password_matches?(1, 4, 'secret')).to be(false)
    end

    it 'is false when --diff fails' do
      capture_calls(status: 1)
      expect(described_class.password_matches?(1, 4, 'secret')).to be(false)
    end

    it 'refuses a password containing a NUL byte, which --diff would compare truncated' do
      calls = capture_calls

      expect { described_class.password_matches?(1, 4, "se\0cret") }.to raise_error(Puppet::Error, %r{NUL byte})
      expect(calls).to be_empty
    end
  end

  # bmc-config prints a value it refuses ("Invalid value '...' for key
  # ..."), and Puppet puts a failed command's output in its error.
  describe 'a password commit that fails' do
    let(:dir) { Dir.mktmpdir }
    let(:password) { 'Q7wP2mK9vX4nB8cL5tR1' }

    after { FileUtils.rm_rf(dir) }

    it 'raises without any of the password in the error' do
      script = File.join(dir, 'bmc-config')
      File.write(script, <<~SH)
        #!/bin/sh
        while read -r key value; do [ "$key" = Password ] && pw=$value; done < "$3"
        echo "Invalid value '$pw' for key 'Password' in section 'User4'"
        echo "Out of Range value '$(printf '%.16s' "$pw")' for key 'Password' in section 'User4'"
        echo "Password   $pw"
        exit 1
      SH
      File.chmod(0o755, script)
      Puppet::Util::Execution.unstub(:execute)
      described_class.stubs(:command).with(:bmcconfig).returns(script)

      expect { described_class.write_password(1, 4, password) }.to raise_error(Puppet::ExecutionFailure) do |e|
        expect(e.message).to include("for key 'Password' in section 'User4'")
        slices = (0..(password.length - 4)).flat_map { |i| (4..(password.length - i)).map { |n| password[i, n] } }
        expect(slices.select { |slice| e.message.include?(slice) }).to be_empty
      end
    end
  end

  describe '.bmcconfig_exec' do
    it 'passes an argv array that keeps stderr and is redacted, and fails on error with the output scrubbed' do
      Puppet::Util::Execution.unstub(:execute)
      described_class.stubs(:command).with(:bmcconfig).returns('/usr/sbin/bmc-config')
      argv = ['/usr/sbin/bmc-config', '--commit', '--key-pair', 'User4:Username=bob', '--lan-channel-number', '1']
      options = { failonfail: false, combine: true, sensitive: true }
      Puppet::Util::Execution.expects(:execute).with(argv, options).returns(result("bad s3cret\n", 1))

      expect { described_class.bmcconfig_exec(argv.drop(1), sensitive: true, redact: ['s3cret']) }
        .to raise_error(Puppet::ExecutionFailure, "Execution of '[redacted]' returned 1: bad [redacted]")
    end

    it 'leaves the failure of a command that is not sensitive to Puppet' do
      Puppet::Util::Execution.unstub(:execute)
      described_class.stubs(:command).with(:bmcconfig).returns('/usr/sbin/bmc-config')
      Puppet::Util::Execution.expects(:execute).with(anything, { failonfail: true, combine: true }).raises(Puppet::ExecutionFailure, 'commit failed')

      expect { described_class.bmcconfig_exec(%w[--commit --key-pair User4:Enable_User=No]) }.to raise_error(Puppet::ExecutionFailure, 'commit failed')
    end
  end

  # Stub bmcconfig_exec, recording each call with the --filename it reads.
  def capture_calls(output: '', status: 0, raises: nil)
    calls = []
    stub = described_class.stubs(:bmcconfig_exec).with do |argv, _opts = {}|
      file = argv[argv.index('--filename') + 1] if argv.include?('--filename')
      calls << SecretFileCapture.call(argv, file)
      true
    end
    raises ? stub.raises(raises) : stub.returns(result(output, status))
    calls
  end
end
