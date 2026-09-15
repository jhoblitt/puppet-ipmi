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

    it 'returns an empty list for empty output' do
      expect(described_class.parse_user_list('')).to eq([])
      expect(described_class.parse_user_list(nil)).to eq([])
    end
  end

  describe '.read_users' do
    it 'queries access only for named slots that could be enabled' do
      described_class.expects(:ipmitool_exec).with(%w[user list 1]).returns(hp_list)
      %w[2 3 4 10].each do |id|
        status = 'enabled'
        status = 'disabled' if id == '3'
        described_class.expects(:ipmitool_exec).with(['channel', 'getaccess', '1', id]).returns("Enable Status    : #{status}\n")
      end

      users = described_class.read_users(1)

      expect(users.select { |u| u[:enabled] }.map { |u| u[:id] }).to eq([2, 4, 10])
    end

    it 'propagates a failing user list' do
      failure = Puppet::ExecutionFailure.new('Unable to establish LAN session')
      described_class.expects(:ipmitool_exec).with(%w[user list 1]).raises(failure)

      expect { described_class.read_users(1) }.to raise_error(Puppet::ExecutionFailure)
    end
  end

  describe 'writes' do
    it 'sets a name' do
      described_class.expects(:ipmitool_exec).with(%w[user set name 4 bob])
      described_class.write_name(1, 4, 'bob')
    end

    it 'sets a password with 16-byte capacity' do
      described_class.expects(:ipmitool_exec).with(%w[user set password 4 secret 16], sensitive: true)
      described_class.write_password(1, 4, 'secret')
    end

    it 'sets a password with 20-byte capacity' do
      pw = 'a' * 20
      described_class.expects(:ipmitool_exec).with(['user', 'set', 'password', '4', pw, '20'], sensitive: true)
      described_class.write_password(1, 4, pw)
    end

    it 'sets privilege and channel access' do
      seq = sequence('priv')
      described_class.expects(:ipmitool_exec).with(%w[user priv 4 3 1]).in_sequence(seq)
      described_class.expects(:ipmitool_exec).with(%w[channel setaccess 1 4 callin=on ipmi=on link=on privilege=3]).in_sequence(seq)
      described_class.write_priv(1, 4, 3)
    end

    it 'enables access in order' do
      seq = sequence('enable')
      described_class.expects(:ipmitool_exec).with(%w[user priv 4 4 1]).in_sequence(seq)
      described_class.expects(:ipmitool_exec).with(%w[user enable 4]).in_sequence(seq)
      described_class.expects(:ipmitool_exec).with(%w[sol payload enable 1 4]).in_sequence(seq)
      described_class.expects(:ipmitool_exec).with(%w[channel setaccess 1 4 callin=on ipmi=on link=on privilege=4]).in_sequence(seq)
      described_class.write_access(1, 4, true, 4)
    end

    it 'revokes access before disabling' do
      seq = sequence('disable')
      described_class.expects(:ipmitool_exec).with(%w[channel setaccess 1 4 callin=off ipmi=off link=off privilege=15]).in_sequence(seq)
      described_class.expects(:ipmitool_exec).with(%w[user priv 4 15 1]).in_sequence(seq)
      described_class.expects(:ipmitool_exec).with(%w[user disable 4]).in_sequence(seq)
      described_class.expects(:ipmitool_exec).with(%w[sol payload disable 1 4]).in_sequence(seq)
      described_class.write_access(1, 4, false, 15)
    end
  end

  describe '.password_matches?' do
    it 'accepts a 16-byte password stored in the 16-byte form' do
      described_class.expects(:ipmitool_exec).with(%w[user test 4 16 secret], sensitive: true, failonfail: false).returns(result('', 0))
      expect(described_class.password_matches?(1, 4, 'secret')).to be(true)
    end

    it 'accepts a short password stored in the 20-byte form' do
      described_class.expects(:ipmitool_exec).with(%w[user test 4 16 secret], sensitive: true, failonfail: false).returns(result('', 1))
      described_class.expects(:ipmitool_exec).with(%w[user test 4 20 secret], sensitive: true, failonfail: false).returns(result('', 0))
      expect(described_class.password_matches?(1, 4, 'secret')).to be(true)
    end

    it 'tests only the 20-byte form for long passwords' do
      pw = 'a' * 20
      described_class.expects(:ipmitool_exec).with(['user', 'test', '4', '20', pw], sensitive: true, failonfail: false).returns(result('', 1))
      expect(described_class.password_matches?(1, 4, pw)).to be(false)
    end
  end

  describe '.ipmitool_exec' do
    it 'passes an argv array that fails on error, keeps stderr and is redacted' do
      Puppet::Util::Execution.unstub(:execute)
      argv = ['/usr/bin/ipmitool', 'user', 'set', 'password', '4', 'pw', '16']
      options = { failonfail: true, combine: true, sensitive: true }
      Puppet::Util::Execution.expects(:execute).with(argv, options).returns(result(''))

      described_class.ipmitool_exec(%w[user set password 4 pw 16], sensitive: true)
    end
  end
end
