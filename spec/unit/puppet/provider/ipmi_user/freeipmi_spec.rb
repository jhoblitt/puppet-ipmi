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

      expect(admin).to eq(id: 2, name: 'ADMIN', priv: 4, enabled: true)
    end

    it 'reports unset slots as empty and disabled' do
      expect(users.find { |u| u[:id] == 3 }).to eq(id: 3, name: '', priv: 0, enabled: false)
    end

    it 'treats <username-not-set-yet> as empty' do
      output = "Section User2\n        Username                                      <username-not-set-yet>\nEndSection\n"

      expect(described_class.parse_checkout(output)).to eq([{ id: 2, name: '', priv: 0, enabled: false }])
    end

    it 'returns an empty list for empty output' do
      expect(described_class.parse_checkout('')).to eq([])
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

    it 'sets a password as sensitive' do
      described_class.expects(:bmc_config_set).with('User4', 'Password', 'secret', channel: 1, sensitive: true)
      described_class.write_password(1, 4, 'secret')
    end

    it 'sets the privilege limit by name' do
      described_class.expects(:bmc_config_set).with('User4', 'Lan_Privilege_Limit', 'Operator', channel: 1)
      described_class.write_priv(1, 4, 3)
    end

    it 'enables access in order' do
      seq = sequence('enable')
      [
        %w[Lan_Privilege_Limit Administrator], %w[Enable_User Yes], %w[Lan_Enable_IPMI_Msgs Yes],
        %w[Lan_Enable_Link_Auth Yes], %w[SOL_Payload_Access Yes]
      ].each do |key, value|
        described_class.expects(:bmc_config_set).with('User4', key, value, channel: 1).in_sequence(seq)
      end
      described_class.write_access(1, 4, true, 4)
    end

    it 'disables access in order' do
      seq = sequence('disable')
      [
        %w[Lan_Privilege_Limit No_Access], %w[Enable_User No], %w[Lan_Enable_IPMI_Msgs No],
        %w[Lan_Enable_Link_Auth No], %w[SOL_Payload_Access No]
      ].each do |key, value|
        described_class.expects(:bmc_config_set).with('User4', key, value, channel: 1).in_sequence(seq)
      end
      described_class.write_access(1, 4, false, 15)
    end

    it 'raises when a value contains whitespace, without echoing it' do
      expect { described_class.bmc_config_set('User4', 'Password', 'has space', channel: 1, sensitive: true) }.
        to raise_error(Puppet::Error) { |e| expect(e.message).not_to include('has space') }
    end
  end

  describe '.password_matches?' do
    it 'is true when --diff reports no mismatch' do
      described_class.expects(:bmcconfig_exec).with(['--diff', '--key-pair', 'User4:Password=secret'], failonfail: false, sensitive: true).returns(result(''))
      expect(described_class.password_matches?(1, 4, 'secret')).to be(true)
    end

    it 'is false when --diff reports a mismatch' do
      described_class.expects(:bmcconfig_exec).returns(result("User4:Password - differs\n", 1))
      expect(described_class.password_matches?(1, 4, 'secret')).to be(false)
    end

    it 'is false when --diff fails' do
      described_class.expects(:bmcconfig_exec).returns(result('', 1))
      expect(described_class.password_matches?(1, 4, 'secret')).to be(false)
    end
  end

  describe '.bmcconfig_exec' do
    it 'passes an argv array that fails on error, keeps stderr and is redacted' do
      Puppet::Util::Execution.unstub(:execute)
      argv = ['/usr/sbin/bmc-config', '--commit', '--key-pair', 'User4:Password=pw', '--lan-channel-number', '1']
      options = { failonfail: true, combine: true, sensitive: true }
      Puppet::Util::Execution.expects(:execute).with(argv, options).returns(result(''))

      described_class.bmcconfig_exec(['--commit', '--key-pair', 'User4:Password=pw', '--lan-channel-number', '1'], sensitive: true)
    end
  end
end
