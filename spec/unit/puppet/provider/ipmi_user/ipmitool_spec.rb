# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_user'

describe Puppet::Type.type(:ipmi_user).provider(:ipmitool) do
  let(:type) { Puppet::Type.type(:ipmi_user) }
  let(:fixtures) { 'spec/fixtures/unit/puppet/provider/ipmi_user' }
  let(:asus_list) { File.read("#{fixtures}/ipmitool_user_list_asus.txt") }
  let(:supermicro_list) { File.read("#{fixtures}/ipmitool_user_list_supermicro.txt") }
  let(:hp_list) { File.read("#{fixtures}/ipmitool_user_list_hp.txt") }

  before do
    described_class.stubs(:suitable?).returns(true)
    Puppet::Util::Execution.expects(:execute).never
  end

  it_behaves_like 'command-confined provider', :ipmitool

  def result(output, status = 0)
    Puppet::Util::Execution::ProcessOutput.new(output, status)
  end

  it 'includes the shared user logic' do
    expect(described_class.ancestors).to include(PuppetX::Ipmi::Provider::UserLogic)
  end

  describe '.parse_user_list' do
    it 'treats HP (Empty User) slots as empty' do
      users = described_class.parse_user_list(hp_list)

      expect(users.find { |u| u[:id] == 5 }[:name]).to eq('')
    end

    it 'parses names and privileges' do
      users = described_class.parse_user_list(hp_list)

      expect(users.find { |u| u[:id] == 4 }).to eq(id: 4, name: 'SLAM', priv: 4)
      expect(users.find { |u| u[:id] == 5 }[:priv]).to eq(15)
      expect(users.find { |u| u[:id] == 10 }[:priv]).to eq(2)
    end

    it 'reports unknown privilege names as 0' do
      users = described_class.parse_user_list(supermicro_list)

      expect(users.first[:priv]).to eq(0)
    end

    it 'reads OEM and any other privilege ipmitool prints as Unknown by number, and other text as nil' do
      expect(%w[OEM CALLBACK].map { |text| described_class.parse_priv(text) } +
             ['Unknown (0x0A)', 'garbled'].map { |text| described_class.parse_priv(text) }).to eq([5, 1, 10, nil])
    end

    it 'returns an empty list for empty output' do
      expect(described_class.parse_user_list('')).to eq([])
      expect(described_class.parse_user_list(nil)).to eq([])
    end
  end

  describe '.lan_channels' do
    def info(medium)
      result("Channel 0x1 info:\n  Channel Medium Type   : #{medium}\n  Channel Protocol Type : IPMB-1.0\n")
    end

    # How ipmitool 1.8.18 fails `channel info` with a completion code.
    def failed(text)
      result("IPMI command failed: #{text}\nUnable to Get Channel Info\n", 1)
    end

    it 'probes channels 1 to 11 and keeps those whose medium is a LAN, skipping those the BMC does not have' do
      outputs = { 1 => info('802.3 LAN'), 3 => info('Other LAN'), 7 => info('IPMB (I2C)'), 11 => info('System Interface') }
      (1..11).each do |channel|
        output = outputs.fetch(channel) { failed('Invalid data field in request') }
        described_class.expects(:ipmitool_exec).with(['channel', 'info', channel.to_s], failonfail: false).returns(output)
      end

      expect(described_class.lan_channels).to eq([1, 3])
    end

    it 'fails, rather than skip the channel, when its probe fails for any other reason' do
      [failed('Node busy'), result("IPMI response is NULL.\nUnable to Get Channel Info\n", 1), result("Could not open device\n", 1)].each do |output|
        described_class.stubs(:ipmitool_exec).with(%w[channel info 1], failonfail: false).returns(info('802.3 LAN'))
        described_class.stubs(:ipmitool_exec).with(%w[channel info 2], failonfail: false).returns(output)

        expect { described_class.lan_channels }.to raise_error(Puppet::Error, %r{channel info 2 failed .*#{Regexp.escape(output.lines.first.strip)}})
      end
    end
  end

  describe '.read_table' do
    def list(privs)
      "ID  Name             Callin  Link Auth  IPMI Msg   Channel Priv Limit\n" \
        "2   ADMIN            true    false      true       #{privs[0]}\n" \
        "3   SLAM             true    false      true       #{privs[1]}\n" \
        "4   DISABLED_4       true    false      true       #{privs[2]}\n" \
        "5   (Empty User)     true    false      true       #{privs[3]}\n"
    end

    def getaccess(statuses)
      records = statuses.map do |id, status|
        record = "\nUser ID              : #{id}\nUser Name            : x\nPrivilege Level      : NO ACCESS\n"
        status ? "#{record}Enable Status        : #{status}\n" : record
      end
      "Maximum User IDs     : 5\nEnabled User IDs     : 2\n#{records.join}"
    end

    def read_with(statuses)
      described_class.expects(:ipmitool_exec).with(%w[user list 1]).returns(list(['ADMINISTRATOR', 'NO ACCESS', 'NO ACCESS', 'NO ACCESS']))
      described_class.expects(:ipmitool_exec).with(%w[user list 2]).returns(list(['ADMINISTRATOR', 'OPERATOR', 'NO ACCESS', 'Unknown (0x00)']))
      described_class.expects(:ipmitool_exec).with(%w[channel getaccess 1]).returns(getaccess(statuses))
      described_class.read_table([1, 2])
    end

    it 'reads each slot privilege on every channel, and every slot Enable Status from one getaccess' do
      expect(read_with(2 => 'enabled', 3 => 'disabled', 4 => 'enabled', 5 => 'disabled')).to eq(
        [
          { id: 2, name: 'ADMIN', status: :enabled, privs: { 1 => 4, 2 => 4 } },
          { id: 3, name: 'SLAM', status: :disabled, privs: { 1 => 15, 2 => 3 } },
          { id: 4, name: 'DISABLED_4', status: :enabled, privs: { 1 => 15, 2 => 15 } },
          { id: 5, name: '', status: :disabled, privs: { 1 => 15, 2 => 0 } },
        ],
      )
    end

    it 'reports the status as unknown when the BMC does, or ipmitool prints none' do
      statuses = read_with(2 => 'unknown', 3 => nil, 4 => 'reserved', 5 => 'disabled').to_h { |u| [u[:id], u[:status]] }

      expect(statuses).to eq(2 => :unknown, 3 => :unknown, 4 => :unknown, 5 => :disabled)
    end

    it 'propagates a failing user list' do
      failure = Puppet::ExecutionFailure.new('Unable to establish LAN session')
      described_class.expects(:ipmitool_exec).with(%w[user list 1]).raises(failure)

      expect { described_class.read_table([1]) }.to raise_error(Puppet::ExecutionFailure)
    end
  end

  describe 'writes' do
    it 'sets a name' do
      described_class.expects(:ipmitool_exec).with(%w[user set name 4 bob])
      described_class.write_name(1, 4, 'bob')
    end

    describe 'a password' do
      it 'of 16 bytes or fewer is set at the prompt, from a 0600 file, never in argv' do
        pw = %(p#ss w~rd"'x)
        calls = capture_calls
        described_class.write_password(1, 4, pw)

        expect(calls.map(&:argv)).to eq([%w[user set password 4]])
        expect(calls.first).to have_attributes(mode: 0o600, content: "#{pw}\n#{pw}\n")
        expect(File.exist?(calls.first.file)).to be(false)
      end

      it 'of 17 to 20 bytes is set in the 20-byte form through a 0600 exec file, never in argv' do
        pw = "it's a long passw0rd"
        calls = capture_calls
        described_class.write_password(1, 4, pw)

        expect(calls.map(&:argv)).to eq([['exec', calls.first.file]])
        expect(calls.first).to have_attributes(mode: 0o600, content: %(user set password 4 "#{pw}" 20\n))
        expect(File.exist?(calls.first.file)).to be(false)
      end

      it 'of 17 to 20 bytes is written bare when it has no whitespace or quotes' do
        pw = "a~b#{'c' * 15}"
        calls = capture_calls
        described_class.write_password(1, 4, pw)

        expect(calls.first.content).to eq("user set password 4 #{pw} 20\n")
      end

      it 'of 17 to 20 bytes that ipmitool exec cannot carry is refused without running anything' do
        calls = capture_calls
        ["#{'a' * 17}#", "#{'a' * 15} b'\"", "#{'a' * 16} ~b", "#{'a' * 16}\tb", "#{'a' * 16}\0b"].each do |pw|
          expect { described_class.write_password(1, 4, pw) }.to raise_error(Puppet::Error, %r{cannot pass}) { |e| expect(e.message).not_to include(pw) }
        end
        expect(calls).to be_empty
      end

      it 'containing a newline is refused without running anything' do
        calls = capture_calls

        expect { described_class.write_password(1, 4, "pass\nword") }.to raise_error(Puppet::Error, %r{newline})
        expect(calls).to be_empty
      end

      it 'of 16 bytes or fewer containing a NUL byte, which the prompt would cut short, is refused without running anything' do
        calls = capture_calls

        expect { described_class.write_password(1, 4, "se\0cret") }.to raise_error(Puppet::Error, %r{NUL byte}) { |e| expect(e.message).not_to include("se\0cret") }
        expect(calls).to be_empty
      end

      it 'file is removed when the command fails' do
        calls = capture_calls(raises: Puppet::ExecutionFailure.new('Set User Password command failed (user 4)'))

        expect { described_class.write_password(1, 4, 'secret') }.to raise_error(Puppet::ExecutionFailure)
        expect(calls.first.mode).to eq(0o600)
        expect(File.exist?(calls.first.file)).to be(false)
      end
    end

    it 'sets privilege and channel access' do
      seq = sequence('priv')
      described_class.expects(:ipmitool_exec).with(%w[user priv 4 3 1]).in_sequence(seq)
      described_class.expects(:ipmitool_exec).with(%w[channel setaccess 1 4 callin=on ipmi=on link=on privilege=3]).in_sequence(seq)
      described_class.write_priv(1, 4, 3)
    end

    describe 'enabling' do
      # Expect the writes up to SOL in `seq`; either named write may raise.
      def expect_enable(seq, priv_while_disabled: nil, sol: nil)
        first_priv = described_class.expects(:ipmitool_exec).with(%w[user priv 4 4 1]).in_sequence(seq)
        first_priv.raises(priv_while_disabled) if priv_while_disabled
        described_class.expects(:ipmitool_exec).with(%w[user enable 4]).in_sequence(seq)
        described_class.expects(:ipmitool_exec).with(%w[user priv 4 4 1]).in_sequence(seq)
        sol_write = described_class.expects(:ipmitool_exec).with(%w[sol payload enable 1 4]).in_sequence(seq)
        sol_write.raises(sol) if sol
      end

      it 'writes the privilege before and after enabling the user, then SOL and channel access' do
        seq = sequence('enable')
        expect_enable(seq)
        described_class.expects(:ipmitool_exec).with(%w[channel setaccess 1 4 callin=on ipmi=on link=on privilege=4]).in_sequence(seq)

        described_class.grant_access(1, 4, 4)
      end

      it 'tolerates a privilege write refused while the user is disabled' do
        seq = sequence('enable')
        expect_enable(seq, priv_while_disabled: Puppet::ExecutionFailure.new('refused'))
        described_class.expects(:ipmitool_exec).with(%w[channel setaccess 1 4 callin=on ipmi=on link=on privilege=4]).in_sequence(seq)

        expect { described_class.grant_access(1, 4, 4) }.not_to raise_error
      end

      it 'disables the user again and re-raises when a write after enabling fails' do
        seq = sequence('enable')
        expect_enable(seq, sol: Puppet::ExecutionFailure.new('sol failed'))
        described_class.expects(:ipmitool_exec).with(%w[user disable 4]).in_sequence(seq)

        expect { described_class.grant_access(1, 4, 4) }.to raise_error(Puppet::ExecutionFailure, 'sol failed')
      end

      it 'keeps the original error when disabling the user again also fails' do
        seq = sequence('enable')
        expect_enable(seq, sol: Puppet::ExecutionFailure.new('sol failed'))
        described_class.expects(:ipmitool_exec).with(%w[user disable 4]).in_sequence(seq).raises(Puppet::ExecutionFailure, 'disable failed')
        Puppet.expects(:err).with(regexp_matches(%r{slot 4 .*may be left enabled.*disable failed}))

        expect { described_class.grant_access(1, 4, 4) }.to raise_error(Puppet::ExecutionFailure, 'sol failed')
      end
    end

    describe 'disabling' do
      # Expect the revoke writes and `user disable` in `seq`; each named
      # write raises the given error.
      def expect_disable(seq, setaccess: nil, priv: nil, disable: nil)
        write = described_class.expects(:ipmitool_exec).with(%w[channel setaccess 1 4 callin=off ipmi=off link=off privilege=15]).in_sequence(seq)
        write.raises(setaccess) if setaccess
        write = described_class.expects(:ipmitool_exec).with(%w[user priv 4 15 1]).in_sequence(seq)
        write.raises(priv) if priv
        described_class.expects(:ipmitool_exec).with(%w[sol payload disable 1 4]).in_sequence(seq)
        write = described_class.expects(:ipmitool_exec).with(%w[user disable 4]).in_sequence(seq)
        write.raises(disable) if disable
      end

      it 'revokes channel, privilege and SOL access before disabling' do
        expect_disable(sequence('disable'))
        described_class.revoke_access([1], 4)
      end

      it 'revokes every channel given, then disables the user once' do
        seq = sequence('disable')
        [1, 2].each do |c|
          described_class.expects(:ipmitool_exec).with(['channel', 'setaccess', c.to_s, '4', 'callin=off', 'ipmi=off', 'link=off', 'privilege=15']).in_sequence(seq)
          described_class.expects(:ipmitool_exec).with(['user', 'priv', '4', '15', c.to_s]).in_sequence(seq)
          described_class.expects(:ipmitool_exec).with(['sol', 'payload', 'disable', c.to_s, '4']).in_sequence(seq)
        end
        described_class.expects(:ipmitool_exec).with(%w[user disable 4]).in_sequence(seq)

        described_class.revoke_access([1, 2], 4)
      end

      it 'still revokes the rest and disables the user, then re-raises, when a revoke write fails' do
        expect_disable(sequence('disable'), setaccess: Puppet::ExecutionFailure.new('setaccess failed'))

        expect { described_class.revoke_access([1], 4) }.to raise_error(Puppet::ExecutionFailure, 'setaccess failed')
      end

      it 'keeps the original error when disabling the user after a failed revoke also fails' do
        expect_disable(sequence('disable'), setaccess: Puppet::ExecutionFailure.new('setaccess failed'),
                                            disable: Puppet::ExecutionFailure.new('disable failed'))
        Puppet.expects(:err).with(regexp_matches(%r{slot 4 .*may be left enabled.*disable failed}))

        expect { described_class.revoke_access([1], 4) }.to raise_error(Puppet::ExecutionFailure, 'setaccess failed')
      end

      it 'tolerates permission changes that an already disabled user refuses' do
        expect_disable(sequence('disable'), setaccess: Puppet::ExecutionFailure.new('refused'), priv: Puppet::ExecutionFailure.new('refused'))

        expect { described_class.revoke_access([1], 4, already_disabled: true) }.not_to raise_error
      end

      it 'fails when an already disabled user cannot be disabled' do
        expect_disable(sequence('disable'), disable: Puppet::ExecutionFailure.new('disable failed'))

        expect { described_class.revoke_access([1], 4, already_disabled: true) }.to raise_error(Puppet::ExecutionFailure, 'disable failed')
      end
    end
  end

  describe 'checking values before any write' do
    it 'accepts what the writers can carry' do
      expect { described_class.check_name(1, 4, 'bob') }.not_to raise_error
      expect { described_class.check_password(1, 4, %(p#ss w~rd"'x)) }.not_to raise_error
      expect { described_class.check_password(1, 4, "it's a long passw0rd") }.not_to raise_error
    end

    it 'refuses a username with a NUL byte, which no command line can carry, without echoing it' do
      expect { described_class.check_name(1, 4, "b\0b") }.to raise_error(Puppet::Error, %r{NUL byte}) { |e| expect(e.message).not_to include("b\0b") }
    end

    it 'refuses the passwords write_password refuses, without echoing them' do
      ["pass\nword", "#{'a' * 17}#"].each do |pw|
        expect { described_class.check_password(1, 4, pw) }.to raise_error(Puppet::Error) { |e| expect(e.message).not_to include(pw) }
      end
    end
  end

  describe '.password_matches?' do
    it 'tests the 16-byte form at the prompt, from a 0600 file, never in argv' do
      calls = capture_calls

      expect(described_class.password_matches?(1, 4, 'secret')).to be(true)
      expect(calls.map(&:argv)).to eq([%w[user test 4 16]])
      expect(calls.first).to have_attributes(mode: 0o600, content: "secret\n")
      expect(File.exist?(calls.first.file)).to be(false)
    end

    it 'accepts a short password stored in the 20-byte form' do
      calls = capture_calls(statuses: [1, 0])

      expect(described_class.password_matches?(1, 4, 'secret')).to be(true)
      expect(calls.map(&:argv)).to eq([%w[user test 4 16], %w[user test 4 20]])
    end

    it 'refuses a password the prompt would cut short, without running anything' do
      calls = capture_calls

      ["se\0cret", "se\ncret"].each do |pw|
        expect { described_class.password_matches?(1, 4, pw) }.to raise_error(Puppet::Error) { |e| expect(e.message).not_to include(pw) }
      end
      expect(calls).to be_empty
    end

    it 'tests only the 20-byte form for long passwords' do
      calls = capture_calls(statuses: [1])

      expect(described_class.password_matches?(1, 4, 'a' * 20)).to be(false)
      expect(calls.map(&:argv)).to eq([%w[user test 4 20]])
      expect(calls.first.content).to eq("#{'a' * 20}\n")
    end
  end

  describe '.ipmitool_exec' do
    it 'passes an argv array that keeps stderr and is redacted, and fails on error with the output redacted' do
      Puppet::Util::Execution.unstub(:execute)
      described_class.stubs(:command).with(:ipmitool).returns('/usr/bin/ipmitool')
      argv = ['/usr/bin/ipmitool', '--', 'user', 'set', 'password', '4']
      options = { failonfail: false, combine: true, sensitive: true, stdinfile: '/run/pw' }
      Puppet::Util::Execution.expects(:execute).with(argv, options).returns(result("bad s3cret\n", 1))

      expect { described_class.ipmitool_exec(%w[user set password 4], sensitive: true, stdinfile: '/run/pw', redact: ['s3cret']) }
        .to raise_error(Puppet::ExecutionFailure, "Execution of '[redacted]' returned 1: bad [redacted]")
    end

    it 'keeps the password out of a failed write' do
      calls = []
      described_class.stubs(:ipmitool_exec).with do |argv, opts = {}|
        calls << [argv, opts[:redact]]
        true
      end
      described_class.write_password(1, 4, 'secret')
      described_class.write_password(1, 4, 'a much longer secret')

      expect(calls.map(&:last)).to eq([['secret'], ['a much longer secret']])
    end
  end

  # Stub ipmitool_exec, recording each call with the file it reads its
  # secret from: its stdin, or the batch file of `ipmitool exec`.
  def capture_calls(statuses: [0], raises: nil)
    calls = []
    stub = described_class.stubs(:ipmitool_exec).with do |argv, opts = {}|
      file = opts[:stdinfile]
      file = argv[1] if argv.first == 'exec'
      calls << SecretFileCapture.call(argv, file)
      true
    end
    raises ? stub.raises(raises) : stub.returns(*statuses.map { |s| result('', s) })
    calls
  end
end
