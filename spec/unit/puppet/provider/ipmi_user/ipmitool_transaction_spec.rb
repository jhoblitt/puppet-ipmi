# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_user'

# Runs real catalogs through the ipmitool provider against a fake
# `ipmitool` on PATH, to check the exact commands a run sends to the BMC.
describe 'ipmi_user through the ipmitool provider' do
  let(:state_dir) { Dir.mktmpdir }
  let(:bmc_options) { {} }
  let(:bmc) { FakeIpmitoolUsers.new(users, **bmc_options) }

  before do
    Puppet[:statedir] = state_dir
    bmc.activate
  end

  after do
    bmc.cleanup
    FileUtils.rm_rf(state_dir)
  end

  def apply(**params)
    apply_all(params)
  end

  def apply_all(*param_sets)
    catalog = Puppet::Resource::Catalog.new
    defaults = { name: 'bob', password: 'secret', channel: 1, provider: 'ipmitool' }
    param_sets.each { |params| catalog.add_resource(Puppet::Type.type(:ipmi_user).new(defaults.merge(params).compact)) }
    catalog.apply.report
  end

  def failures(report)
    report.resource_statuses.values.count(&:failed)
  end

  def changes(report)
    report.resource_statuses.values.count(&:changed)
  end

  {
    'Enable Status: unknown' => 'unknown',
    'no Enable Status line' => nil,
  }.each do |label, status|
    context "with a live ADMINISTRATOR and #{label}" do
      let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'SLAM', 'ADMINISTRATOR']] }
      let(:bmc_options) { { enable_status: status } }
      let(:revoke) do
        [
          'channel setaccess 1 3 callin=off ipmi=off link=off privilege=15', 'user priv 3 15 1',
          'sol payload disable 1 3', 'user disable 3',
        ]
      end

      it 'revokes access for enable => false' do
        expect(failures(apply(name: 'SLAM', user_id: 3, enable: :false, password: nil))).to eq(0)
        expect(bmc.writes).to eq(revoke)
      end

      it 'revokes access, then renames the slot, for ensure => absent' do
        expect(failures(apply(name: 'SLAM', user_id: 3, ensure: :absent, password: nil))).to eq(0)
        expect(bmc.writes).to eq(revoke + ['user set name 3 DISABLED_3'])
      end

      it 'treats enable => true as in sync on the second run' do
        apply(name: 'SLAM', user_id: 3)
        report = apply(name: 'SLAM', user_id: 3)

        expect(changes(report)).to eq(0)
        expect(bmc.writes).to be_empty
      end
    end
  end

  # `user list` prints the privilege on the queried channel only, so a slot
  # with NO ACCESS there can still be enabled, with SOL access.
  context 'with an enabled account that has NO ACCESS on its one LAN channel but SOL access, which neither user list nor getaccess shows' do
    let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'SLAM', 'NO ACCESS']] }
    let(:revoke) do
      [
        'channel setaccess 1 3 callin=off ipmi=off link=off privilege=15', 'user priv 3 15 1',
        'sol payload disable 1 3', 'user disable 3',
      ]
    end

    it 'revokes access and disables it, then renames the slot, for ensure => absent' do
      expect(failures(apply(name: 'SLAM', user_id: 3, ensure: :absent, password: nil))).to eq(0)
      expect(bmc.writes).to eq(revoke + ['user set name 3 DISABLED_3'])
    end

    it 'revokes access and disables it for enable => false' do
      expect(failures(apply(name: 'SLAM', user_id: 3, enable: :false, password: nil))).to eq(0)
      expect(bmc.writes).to eq(revoke)
    end
  end

  # The account is BMC-wide, so revoking it revokes every LAN channel.
  describe 'a slot with a privilege on another LAN channel' do
    let(:users) do
      {
        1 => [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'SLAM', 'NO ACCESS']],
        2 => [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'SLAM', 'ADMINISTRATOR']],
      }
    end

    def revoke
      [1, 2].flat_map do |c|
        ["channel setaccess #{c} 3 callin=off ipmi=off link=off privilege=15", "user priv 3 15 #{c}", "sol payload disable #{c} 3"]
      end + ['user disable 3']
    end

    def enable
      [
        'user priv 3 4 1', 'user enable 3', 'user priv 3 4 1',
        'sol payload enable 1 3', 'channel setaccess 1 3 callin=on ipmi=on link=on privilege=4',
      ]
    end

    # Apply twice; the second run must change nothing.
    def converges(**params)
      expect(failures(apply(**params))).to eq(0)
      first = bmc.writes
      expect(changes(apply(**params))).to eq(0)
      expect(bmc.writes).to eq(first)
      first
    end

    {
      'Enable Status enabled' => 'enabled', 'Enable Status unknown' => 'unknown', 'no Enable Status line' => nil,
    }.each do |label, status|
      context "with #{label}" do
        let(:bmc_options) { { enable_status: status } }

        it 'revokes it on every LAN channel and disables it for enable => false, then stays quiet' do
          expect(converges(name: 'SLAM', user_id: 3, enable: :false, password: nil)).to eq(revoke)
        end

        it 'revokes it on every LAN channel, then renames the slot, for ensure => absent, then stays quiet' do
          expect(converges(name: 'SLAM', user_id: 3, ensure: :absent, password: nil)).to eq(revoke + ['user set name 3 DISABLED_3'])
        end

        it 'revokes it on every LAN channel before taking the slot over, then stays quiet' do
          expect(converges(user_id: 3)).to eq(revoke + ['user set name 3 bob', 'user set password 3'] + enable)
        end

        it 'revokes it on every LAN channel before taking the slot over for enable => false, then stays quiet' do
          expect(converges(user_id: 3, enable: :false, password: nil)).to eq(revoke + ['user set name 3 bob'])
        end
      end
    end

    context 'with Enable Status disabled' do
      let(:bmc_options) { { enable_status: 'disabled', refuse_priv: :always } }

      it 'treats enable => false as in sync, since a BMC refuses permission changes on a disabled account' do
        expect(converges(name: 'SLAM', user_id: 3, enable: :false, password: nil)).to be_empty
      end

      it 'still revokes it on every LAN channel before renaming it for ensure => absent, tolerating refusals' do
        expect(converges(name: 'SLAM', user_id: 3, ensure: :absent, password: nil)).to eq(revoke + ['user set name 3 DISABLED_3'])
      end
    end
  end

  context 'with a slot disabled with no privilege on any LAN channel' do
    let(:users) do
      {
        1 => [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'SLAM', 'NO ACCESS']],
        2 => [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'SLAM', 'NO ACCESS']],
      }
    end
    let(:bmc_options) { { enable_status: 'disabled' } }

    it 'only renames it for ensure => absent' do
      expect(failures(apply(name: 'SLAM', user_id: 3, ensure: :absent, password: nil))).to eq(0)
      expect(bmc.writes).to eq(['user set name 3 DISABLED_3'])
    end
  end

  context 'with one username on two channels, in a slot that holds another account' do
    let(:users) do
      {
        1 => [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'SLAM', 'ADMINISTRATOR']],
        2 => [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'SLAM', 'ADMINISTRATOR']],
      }
    end

    it 'takes the slot over once and gives the user access on both channels, then stays quiet' do
      sets = [{ name: 'bob', user_id: 3 }, { name: 'bob-ch2', username: 'bob', user_id: 3, channel: 2 }]
      expect(failures(apply_all(*sets))).to eq(0)

      expect(bmc.writes.count('user disable 3')).to eq(1)
      expect([bmc.slot(3, 1), bmc.slot(3, 2)]).to all(include(name: 'bob', priv: 'ADMINISTRATOR', status: 'enabled'))
      expect(changes(apply_all(*sets))).to eq(0)
    end
  end

  context 'with NO ACCESS and Enable Status unknown on a BMC that refuses permission changes on a disabled account' do
    let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'SLAM', 'NO ACCESS']] }
    let(:bmc_options) { { enable_status: 'unknown', refuse_priv: :always } }

    it 'still revokes and disables it before renaming for ensure => absent, tolerating the refusal' do
      expect(failures(apply(name: 'SLAM', user_id: 3, ensure: :absent, password: nil))).to eq(0)
      expect(bmc.writes).to eq(
        [
          'channel setaccess 1 3 callin=off ipmi=off link=off privilege=15', 'user priv 3 15 1',
          'sol payload disable 1 3', 'user disable 3', 'user set name 3 DISABLED_3',
        ],
      )
    end
  end

  context 'with a DISABLED_ slot that is enabled' do
    let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'DISABLED_3', 'NO ACCESS'], [4, '', 'NO ACCESS']] }

    it 'allocates an empty slot instead' do
      expect(failures(apply)).to eq(0)
      expect(bmc.writes).to include('user set name 4 bob')
      expect(bmc.writes.grep(%r{ 3( |\z)})).to be_empty
    end
  end

  context 'with an empty slot that is enabled' do
    let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, '', 'NO ACCESS'], [4, '', 'NO ACCESS']] }
    let(:bmc_options) { { enable_status: { 3 => 'enabled' } } }

    it 'allocates another empty slot instead' do
      expect(failures(apply)).to eq(0)
      expect(bmc.writes).to include('user set name 4 bob')
      expect(bmc.writes.grep(%r{ 3( |\z)})).to be_empty
    end
  end

  # User slots are BMC-wide, so a slot is free only when no LAN channel
  # grants it anything, whichever channel the resource is on.
  context 'with a DISABLED_ slot of unknown status that is NO ACCESS on channel 1 but ADMINISTRATOR on channel 2' do
    let(:users) do
      {
        1 => [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'DISABLED_3', 'NO ACCESS'], [4, '', 'NO ACCESS']],
        2 => [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'DISABLED_3', 'ADMINISTRATOR'], [4, '', 'NO ACCESS']],
      }
    end
    let(:bmc_options) { { enable_status: 'unknown' } }

    it 'allocates a slot no LAN channel grants anything to a user on channel 1' do
      expect(failures(apply)).to eq(0)
      expect(bmc.writes).to include('user set name 4 bob')
      expect(bmc.writes.grep(%r{ 3( |\z)})).to be_empty
    end
  end

  # Slot 5 shows NO ACCESS on channel 1 but ADMINISTRATOR on channel 2, and
  # the BMC does not report whether it is enabled.  Prefetch and generate
  # must allocate from the same BMC-wide table, whichever resource comes
  # first.
  describe 'auto users on two LAN channels beside a DISABLED_ slot only one channel shows granted' do
    let(:users) do
      others = [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'carol', 'USER'], [4, 'dave', 'USER'], [6, '', 'NO ACCESS'], [7, '', 'NO ACCESS']]
      { 1 => others + [[5, 'DISABLED_5', 'NO ACCESS']], 2 => others + [[5, 'DISABLED_5', 'ADMINISTRATOR']] }
    end
    let(:bmc_options) { { enable_status: { 5 => 'unknown' } } }

    {
      'channel 1 first' => [{ name: 'amy', purge_duplicates: true }, { name: 'bob', channel: 2, purge_duplicates: true }],
      'channel 2 first' => [{ name: 'bob', channel: 2, purge_duplicates: true }, { name: 'amy', purge_duplicates: true }],
    }.each do |order, sets|
      it "gives them the same free slots with #{order}, never slot 5" do
        expect(failures(apply_all(*sets))).to eq(0)

        expect(bmc.writes.grep(%r{\Auser set name })).to contain_exactly('user set name 6 amy', 'user set name 7 bob')
        expect(bmc.writes.grep(%r{ 5( |\z)})).to be_empty
      end
    end
  end

  describe 'reading the BMC user table' do
    let(:users) do
      {
        1 => [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'bob', 'ADMINISTRATOR']],
        3 => [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'bob', 'NO ACCESS']],
      }
    end

    it 'probes channels 1 to 11 once per run, then reads each LAN channel and every slot once' do
      apply(user_id: 3, purge_duplicates: true)
      reads = bmc.calls.reject { |c| c.start_with?('user test') }

      expect(reads).to eq((1..11).map { |c| "channel info #{c}" } + ['user list 1', 'user list 3', 'channel getaccess 1'])
    end
  end

  describe 'the password' do
    let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, '', 'NO ACCESS'], [4, 'bob', 'ADMINISTRATOR']] }

    def expect_never_in_argv(password)
      expect(bmc.calls).not_to be_empty
      expect(bmc.calls.grep(%r{#{Regexp.escape(password)}})).to be_empty
    end

    it 'is set at the prompt, not on the command line' do
      pw = %(p#ss w~rd"x)
      expect(failures(apply(name: 'amy', user_id: 3, password: pw))).to eq(0)

      expect(bmc.writes).to include('user set password 3')
      expect(bmc.secret_input).to eq([pw, pw])
      expect_never_in_argv(pw)
    end

    it 'of 17 to 20 bytes is set through an exec file, not on the command line' do
      pw = 'a much longer secret'
      expect(failures(apply(name: 'amy', user_id: 3, password: pw))).to eq(0)

      expect(bmc.writes.grep(%r{\Aexec /})).not_to be_empty
      expect(bmc.secret_input).to include(%(user set password 3 "#{pw}" 20))
      expect_never_in_argv(pw)
    end

    it 'is tested at the prompt, not on the command line' do
      pw = %(p#ss w~rd"x)
      report = apply(user_id: 4, password: pw)

      expect(changes(report)).to eq(0)
      expect(bmc.calls).to include('user test 4 16')
      expect(bmc.secret_input).to eq([pw])
      expect_never_in_argv(pw)
    end
  end

  describe 'taking over a slot that holds another, enabled account' do
    let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'SLAM', 'ADMINISTRATOR']] }

    def revoke
      [
        'channel setaccess 1 3 callin=off ipmi=off link=off privilege=15', 'user priv 3 15 1',
        'sol payload disable 1 3', 'user disable 3',
      ]
    end

    def enable
      [
        'user priv 3 4 1', 'user enable 3', 'user priv 3 4 1',
        'sol payload enable 1 3', 'channel setaccess 1 3 callin=on ipmi=on link=on privilege=4',
      ]
    end

    it 'revokes and disables the old account, then renames the slot, sets the password and enables it' do
      expect(failures(apply(user_id: 3))).to eq(0)
      expect(bmc.writes).to eq(revoke + ['user set name 3 bob', 'user set password 3'] + enable)
    end

    it 'revokes and disables the old account before renaming the slot for enable => false' do
      expect(failures(apply(user_id: 3, enable: :false, password: nil))).to eq(0)
      expect(bmc.writes).to eq(revoke + ['user set name 3 bob'])
    end

    it 'refuses a password ipmitool cannot carry before writing anything' do
      expect(failures(apply(user_id: 3, password: "#{'a' * 17}#"))).to eq(1)
      expect(bmc.writes).to be_empty
    end

    it 'refuses a username ipmitool cannot carry before writing anything' do
      expect(failures(apply(username: "b\0b", user_id: 3))).to eq(1)
      expect(bmc.writes).to be_empty
    end

    context 'when a revoke write fails' do
      let(:bmc_options) { { failing: ['channel setaccess'] } }

      it 'still disables the old account and leaves the slot unrenamed' do
        expect(failures(apply(user_id: 3))).to eq(1)
        expect(bmc.writes).to eq(revoke)
      end

      it 'still disables the old account and leaves the slot unrenamed for enable => false' do
        expect(failures(apply(user_id: 3, enable: :false, password: nil))).to eq(1)
        expect(bmc.writes).to eq(revoke)
      end
    end

    context 'when the password write fails' do
      let(:bmc_options) { { failing: ['user set password'] } }

      it 'leaves the renamed slot disabled with no access' do
        expect(failures(apply(user_id: 3))).to eq(1)
        expect(bmc.writes).to eq(revoke + ['user set name 3 bob', 'user set password 3'])
      end
    end
  end

  describe 'enabling a disabled slot' do
    let(:enable_order) do
      [
        'user priv 3 4 1', 'user enable 3', 'user priv 3 4 1',
        'sol payload enable 1 3', 'channel setaccess 1 3 callin=on ipmi=on link=on privilege=4',
      ]
    end

    context 'when the slot is a disabled user being re-enabled' do
      let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'bob', 'NO ACCESS']] }

      it 'writes the privilege before enabling, then the privilege and access, leaving a matching password alone' do
        expect(failures(apply(user_id: 3))).to eq(0)
        expect(bmc.writes).to eq(enable_order)
      end
    end

    context 'when the slot is a disabled user being re-enabled with a new password' do
      let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'bob', 'NO ACCESS']] }
      let(:bmc_options) { { failing: ['user test'] } }

      it 'sets the password once, before enabling' do
        expect(failures(apply(user_id: 3))).to eq(0)
        expect(bmc.writes).to eq(['user set password 3'] + enable_order)
      end
    end

    context 'when the slot is empty' do
      let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, '', 'NO ACCESS']] }

      it 'names the slot and sets the password first, then enables it in the same order' do
        expect(failures(apply(user_id: 3))).to eq(0)
        expect(bmc.writes).to eq(['user set name 3 bob', 'user set password 3'] + enable_order)
      end
    end

    context 'when the BMC refuses privilege changes on a disabled account' do
      let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'bob', 'NO ACCESS']] }
      let(:bmc_options) { { refuse_priv: :while_disabled } }

      it 'tolerates the refusal and writes the privilege once the account is enabled' do
        expect(failures(apply(user_id: 3))).to eq(0)
        expect(bmc.writes).to eq(enable_order)
      end
    end

    context 'when the privilege write fails after enabling' do
      let(:users) { [[2, 'ADMIN', 'ADMINISTRATOR'], [3, 'bob', 'NO ACCESS']] }
      let(:bmc_options) { { refuse_priv: :always } }

      it 'disables the account again and fails the resource' do
        expect(failures(apply(user_id: 3))).to eq(1)
        expect(bmc.writes).to eq(enable_order.first(3) + ['user disable 3'])
      end
    end
  end
end
