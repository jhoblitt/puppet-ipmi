# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_user'

# Runs real catalogs against the in-memory fake BMC to check that
# prefetch, ensure and the property setters cooperate and converge.
describe 'ipmi_user catalog application' do
  let(:type) { Puppet::Type.type(:ipmi_user) }
  let(:table) { FakeUserBmc.table_with({ id: 1 }, { id: 2, name: 'ADMIN', priv: 4, status: :enabled }, { id: 3 }, { id: 4 }) }
  let(:log) { [] }
  let(:state_dir) { Dir.mktmpdir }

  let(:provider) { FakeUserBmc.registered_provider }

  before do
    Puppet[:statedir] = state_dir
    provider.stubs(:suitable?).returns(true)
    provider.fake_table = table
    provider.fake_log = log
    provider.fake_password = 'secret'
    provider.fake_reads = nil
    provider.fake_refuses_revoke = false
  end

  after { FileUtils.rm_rf(state_dir) }

  def apply(**params)
    apply_all(params)
  end

  def apply_all(*param_sets)
    catalog = Puppet::Resource::Catalog.new
    param_sets.each do |params|
      catalog.add_resource(type.new({ name: 'bob', password: 'secret', channel: 1, provider: 'fake_bmc' }.merge(params).compact))
    end
    catalog.apply.report
  end

  def changed_count(report)
    report.resource_statuses.values.count(&:changed)
  end

  def slot(id)
    table.find { |u| u[:id] == id }
  end

  def state(id, channel = 1)
    FakeUserBmc.view(slot(id), channel)
  end

  it 'creates a user on the first run and is idempotent on the second' do
    expect(changed_count(apply(user_id: 3))).to eq(1)
    expect(state(3)).to include(name: 'bob', priv: 4, status: :enabled)

    log.clear
    expect(changed_count(apply(user_id: 3))).to eq(0)
    expect(log).to be_empty
  end

  it 'fails the resource, writing nothing, when the LAN channels cannot be probed' do
    FakeUserBmc.update(slot(2), status: :unknown)
    provider.stubs(:lan_channels).raises(Puppet::Error, 'probe failed')
    report = apply(name: 'ADMIN', user_id: 2, ensure: :absent, password: nil)

    expect(report.resource_statuses.values.count(&:failed)).to eq(1)
    expect(log).to be_empty
  end

  it 'allocates the lowest free slot for user_id auto' do
    apply
    expect(table.find { |u| u[:id] == 3 }[:name]).to eq('bob')
  end

  it 'replaces an account occupying an explicitly selected slot' do
    report = apply(user_id: 2)

    expect(report.resource_statuses.values.count(&:failed)).to eq(0)
    expect(state(2)).to include(name: 'bob', status: :enabled, priv: 4)
    expect(log).to include([:name, 2, 'bob'], [:password, 2, 'secret'])

    log.clear
    expect(changed_count(apply(user_id: 2))).to eq(0)
    expect(log).to be_empty
  end

  it 'takes over an occupied explicit slot for a disabled username, then stays quiet' do
    report = apply(user_id: 2, enable: :false, password: nil)

    expect(report.resource_statuses.values.count(&:failed)).to eq(0)
    expect(state(2)).to include(name: 'bob', status: :disabled, priv: 15)
    expect(log).to eq([[:revoke, 2, [1]], [:name, 2, 'bob']])

    log.clear
    expect(changed_count(apply(user_id: 2, enable: :false, password: nil))).to eq(0)
    expect(log).to be_empty
  end

  it 'reserves a DISABLED_ slot for a disabled auto user, then stays quiet' do
    slot(3)[:name] = 'DISABLED_3'

    expect(changed_count(apply(enable: :false, password: nil))).to eq(1)
    expect(state(3)).to include(name: 'bob', status: :disabled, priv: 15)

    log.clear
    expect(changed_count(apply(enable: :false, password: nil))).to eq(0)
    expect(log).to be_empty
  end

  it 'converges a disabled user and then stays quiet' do
    expect(changed_count(apply(user_id: 3, enable: :false, password: nil))).to eq(1)
    expect(state(3)).to include(name: 'bob', status: :disabled, priv: 15)

    expect(changed_count(apply(user_id: 3, enable: :false, password: nil))).to eq(0)
  end

  it 're-enables a disabled user without writing its privilege while it is disabled, or its matching password' do
    FakeUserBmc.update(slot(3), name: 'bob', priv: 15, status: :disabled)

    expect(changed_count(apply(user_id: 3))).to eq(1)
    expect(log).to eq([[:grant, 3, 4]])
    expect(state(3)).to include(status: :enabled, priv: 4)
  end

  it 're-enables a disabled user with a changed password, writing it once' do
    FakeUserBmc.update(slot(3), name: 'bob', priv: 15, status: :disabled)
    provider.fake_password = 'old'

    expect(changed_count(apply(user_id: 3))).to eq(1)
    expect(log).to eq([[:password, 3, 'secret'], [:grant, 3, 4]])
  end

  it 'stays quiet for unfixable drift on an already disabled slot' do
    # Slot disabled out-of-band while holding a privilege; BMCs refuse
    # permission changes on disabled accounts, so this can never converge.
    FakeUserBmc.update(slot(3), name: 'bob', priv: 4, status: :disabled)

    logs = []
    Puppet.stubs(:info).with do |msg|
      logs << msg if msg.include?('ipmi_user')
      true
    end
    report = apply(user_id: 3, enable: :false, password: nil)

    expect(changed_count(report)).to eq(0)
    expect(log).to be_empty
    expect(logs.join("\n")).to match(%r{disabled.*priv 4}i)
  end

  it 'removes a reserved, disabled user without touching its permissions' do
    apply(user_id: 3, enable: :false, password: nil)
    log.clear

    expect(changed_count(apply(user_id: 3, ensure: :absent, password: nil))).to eq(1)
    expect(log).to eq([[:name, 3, 'DISABLED_3']])
  end

  it 'purges a disabled duplicate without touching its permissions' do
    apply(name: 'old', username: 'bob', user_id: 4, enable: :false, password: nil)
    log.clear
    apply(user_id: 3, purge_duplicates: true)

    expect(log.select { |entry| entry[1] == 4 }).to eq([[:name, 4, 'DISABLED_4']])
  end

  it 'removes an existing user with ensure absent and does nothing for a missing one' do
    expect(changed_count(apply(name: 'ADMIN', user_id: 2, ensure: :absent, password: nil))).to eq(1)
    expect(state(2)).to include(name: 'DISABLED_2', status: :disabled)

    expect(changed_count(apply(name: 'ADMIN', user_id: 2, ensure: :absent, password: nil))).to eq(0)
    expect(changed_count(apply(name: 'ghost', ensure: :absent, password: nil))).to eq(0)
  end

  it 'gives the same slots to several auto resources regardless of catalog order' do
    sets = [{ name: 'zed' }, { name: 'amy' }, { name: 'bob' }]
    apply_all(*sets)
    first = table.map { |u| u[:name] }

    table.each { |u| FakeUserBmc.update(u, name: '', priv: 15, status: :disabled) unless u[:id] == 2 }
    apply_all(*sets.reverse)

    expect(table.map { |u| u[:name] }).to eq(first)
    expect(first).to eq(['', 'ADMIN', 'amy', 'bob'])
  end

  it 'stays quiet on repeated runs with several auto resources' do
    sets = [{ name: 'amy' }, { name: 'bob' }]
    apply_all(*sets)

    expect(changed_count(apply_all(*sets))).to eq(0)
  end

  it 'reports a failure for the resource without a slot and still applies the others' do
    sets = %w[a b c].map { |n| { name: n } }
    report = apply_all(*sets)

    expect(table.map { |u| u[:name] }).to eq(['', 'ADMIN', 'a', 'b'])
    expect(report.resource_statuses.values.count(&:failed)).to eq(1)
  end

  describe 'auto users on different channels' do
    def converges(sets)
      report = apply_all(*sets)
      expect(report.resource_statuses.values.count(&:failed)).to eq(0)
      yield

      log.clear
      expect(changed_count(apply_all(*sets))).to eq(0)
      expect(log).to be_empty
    end

    it 'gives different usernames distinct slots, then stays quiet' do
      converges([{ name: 'alice', channel: 2 }, { name: 'bob' }]) do
        expect(table.map { |u| u[:name] }).to eq(['', 'ADMIN', 'alice', 'bob'])
      end
    end

    it 'gives one username a single slot on every channel' do
      converges([{ name: 'bob' }, { name: 'bob-ch2', username: 'bob', channel: 2 }]) do
        expect(table.map { |u| u[:name] }).to eq(['', 'ADMIN', 'bob', ''])
      end
    end

    it 'gives an auto username the slot an explicit resource names for it on another channel' do
      converges([{ name: 'bob', user_id: 4 }, { name: 'bob-ch2', username: 'bob', channel: 2 }]) do
        expect(table.map { |u| u[:name] }).to eq(['', 'ADMIN', '', 'bob'])
      end
    end
  end

  # Prefetch runs once per provider, but the BMC's slots are shared by the
  # resources of every provider, as purge_duplicates' lookup knows.
  describe 'resources with different providers on one BMC' do
    before do
      peer = FakeUserBmc.registered_provider(:fake_bmc_peer)
      peer.stubs(:suitable?).returns(true)
      peer.fake_table = table
      peer.fake_log = log
      peer.fake_password = 'secret'
      FakeUserBmc.update(slot(3), name: 'bob', priv: 4, status: :enabled)
      FakeUserBmc.update(slot(4), name: 'bob', priv: 4, status: :enabled)
    end

    it 'allocates them together, so an auto user keeps a slot that no other provider resource names' do
      sets = [{ name: 'bob', priv: 2, purge_duplicates: true }, { name: 'carol', user_id: 3, provider: 'fake_bmc_peer' }]
      report = apply_all(*sets)

      expect(report.resource_statuses.values.count(&:failed)).to eq(0)
      expect(log.select { |entry| entry[1] == 3 && entry[0] == :priv }).to be_empty
      expect(state(3)).to include(name: 'carol', status: :enabled, priv: 4)
      expect(state(4)).to include(name: 'bob', status: :enabled, priv: 2)

      log.clear
      expect(changed_count(apply_all(*sets))).to eq(0)
      expect(log).to be_empty
    end
  end

  describe 'an explicit user_id on the slot of an auto user' do
    before { FakeUserBmc.update(slot(3), name: 'alice', priv: 4, status: :enabled) }

    {
      'enabled' => { user_id: 3 },
      'disabled' => { user_id: 3, enable: :false, password: nil },
    }.each do |state, bob|
      it "moves the auto user to a free slot when the explicit user is #{state}, then stays quiet" do
        sets = [bob, { name: 'alice' }]
        report = apply_all(*sets)

        expect(report.resource_statuses.values.count(&:failed)).to eq(0)
        expect(slot(3)[:name]).to eq('bob')
        expect(state(4)).to include(name: 'alice', status: :enabled, priv: 4)

        log.clear
        expect(changed_count(apply_all(*sets))).to eq(0)
        expect(log).to be_empty
      end
    end
  end

  # A BMC that does not report Enable Status may have no enable bits, so
  # only the privilege keeps such an account out.
  describe 'renaming a slot whose account the BMC does not report enabled or disabled' do
    before { FakeUserBmc.update(slot(2), status: :unknown) }

    {
      'retiring it' => [{ name: 'ADMIN', user_id: 2, ensure: :absent, password: nil }, 'DISABLED_2'],
      'taking it over' => [{ user_id: 2 }, 'bob'],
      'taking it over for a disabled user' => [{ user_id: 2, enable: :false, password: nil }, 'bob'],
    }.each do |label, (params, new_name)|
      it "fails #{label} without renaming it while the BMC refuses to revoke its privilege, then tries again" do
        provider.fake_refuses_revoke = true

        2.times do
          log.clear
          report = apply(**params)

          expect(report.resource_statuses.values.count(&:failed)).to eq(1)
          expect(log).to eq([[:revoke, 2, [1]]])
          expect(state(2)).to include(name: 'ADMIN', priv: 4)
        end

        provider.fake_refuses_revoke = false
        expect(apply(**params).resource_statuses.values.count(&:failed)).to eq(0)
        expect(slot(2)[:name]).to eq(new_name)
      end

      it "renames it when #{label} once the BMC accepts the revoke" do
        report = apply(**params)

        expect(report.resource_statuses.values.count(&:failed)).to eq(0)
        expect(log.first(2)).to eq([[:revoke, 2, [1]], [:name, 2, new_name]])
      end
    end
  end

  describe 'a present and an absent resource for the same username' do
    before { FakeUserBmc.update(slot(3), name: 'alice', priv: 4, status: :enabled) }

    {
      'both auto' => [{ name: 'alice' }, { name: 'alice-gone', username: 'alice', ensure: :absent, password: nil }],
      'absent first' => [{ name: 'alice-gone', username: 'alice', ensure: :absent, password: nil }, { name: 'alice' }],
      'both in slot 3' => [{ name: 'alice', user_id: 3 }, { name: 'alice-gone', username: 'alice', user_id: 3, ensure: :absent, password: nil }],
    }.each do |label, sets|
      it "rejects the catalog when #{label} instead of letting them fight over the slot" do
        expect { apply_all(*sets) }.to raise_error(Puppet::Error, %r{pre-run checks failed})
        expect(log).to be_empty
        expect(slot(3)[:name]).to eq('alice')
      end
    end
  end

  # User slots and names are BMC-wide, so these conflict across channels too.
  describe 'resources on different channels that would fight over a slot' do
    before { FakeUserBmc.update(slot(3), name: 'alice', priv: 4, status: :enabled) }

    {
      'two usernames claim one explicit slot' => [{ name: 'alice', user_id: 3 }, { name: 'bob', user_id: 3, channel: 2 }],
      'one username claims two explicit slots' => [{ name: 'bob', user_id: 3 }, { name: 'bob-ch2', username: 'bob', user_id: 4, channel: 2 }],
      'an absent auto resource names a present username' =>
        [{ name: 'alice' }, { name: 'alice-gone', username: 'alice', channel: 2, ensure: :absent, password: nil }],
      'an absent resource names the explicit slot of a present username' =>
        [{ name: 'alice', user_id: 3 }, { name: 'alice-gone', username: 'alice', user_id: 3, channel: 2, ensure: :absent, password: nil }],
      'one username is enabled on one channel and disabled on another' =>
        [{ name: 'alice' }, { name: 'alice-ch2', username: 'alice', channel: 2, enable: :false, password: nil }],
      'one username has a different password on each channel' =>
        [{ name: 'alice' }, { name: 'alice-ch2', username: 'alice', channel: 2, password: 'other' }],
    }.each do |label, sets|
      it "rejects the catalog when #{label}" do
        expect { apply_all(*sets) }.to raise_error(Puppet::Error, %r{pre-run checks failed})
        expect(log).to be_empty
        expect(slot(3)[:name]).to eq('alice')
      end
    end
  end

  describe 'an absent resource with an explicit id for the username of an auto user' do
    let(:table) do
      FakeUserBmc.table_with(
        { id: 1 }, { id: 2, name: 'ADMIN', priv: 4, status: :enabled }, { id: 3 }, { id: 4 },
        { id: 5, name: 'ops', priv: 4, status: :enabled }, { id: 6 }, { id: 7, name: 'ops', priv: 4, status: :enabled }
      )
    end

    def converges(sets)
      report = apply_all(*sets)
      expect(report.resource_statuses.values.count(&:failed)).to eq(0)
      yield

      log.clear
      expect(changed_count(apply_all(*sets))).to eq(0)
      expect(log).to be_empty
    end

    it 'moves the auto user to another slot holding the username and retires the named one, then stays quiet' do
      converges([{ name: 'ops' }, { name: 'ops-old', username: 'ops', user_id: 5, ensure: :absent, password: nil }]) do
        expect(state(5)).to include(name: 'DISABLED_5', status: :disabled)
        expect(state(7)).to include(name: 'ops', status: :enabled)
      end
    end

    it 'moves the auto user to a free slot when it holds no other, then stays quiet' do
      FakeUserBmc.update(slot(7), name: '', priv: 15, status: :disabled)

      converges([{ name: 'ops' }, { name: 'ops-old', username: 'ops', user_id: 5, ensure: :absent, password: nil }]) do
        expect(state(5)).to include(name: 'DISABLED_5', status: :disabled)
        expect(state(3)).to include(name: 'ops', status: :enabled)
      end
    end
  end

  describe 'reading the BMC user table' do
    def sets
      [
        { name: 'bob', user_id: 3, purge_duplicates: true }, { name: 'amy', user_id: 4, purge_duplicates: true },
        { name: 'bob-ch2', username: 'bob', user_id: 3, channel: 2, purge_duplicates: true },
      ]
    end

    before do
      FakeUserBmc.update(slot(3), name: 'bob', priv: 4, status: :enabled)
      FakeUserBmc.update(slot(4), name: 'amy', priv: 4, status: :enabled)
      provider.fake_reads = []
    end

    it 'reads the table of every channel once per run, for generate and prefetch together' do
      expect(changed_count(apply_all(*sets))).to eq(0)
      expect(provider.fake_reads).to eq([[1, 2]])
    end

    it 'reads the table again on the next run' do
      2.times { apply_all(*sets) }

      expect(provider.fake_reads).to eq([[1, 2], [1, 2]])
    end

    # A write whose effect the provider knows updates its snapshot instead.
    it 'reads the table once for a resource whose password and privilege change' do
      provider.fake_password = 'old'

      expect(changed_count(apply(user_id: 3, priv: 3))).to eq(1)
      expect(log).to eq([[:password, 3, 'secret'], [:priv, 3, 3]])
      expect(provider.fake_reads).to eq([[1]])
    end

    it 'reads the table once for a resource whose password, privilege and enable change' do
      FakeUserBmc.update(slot(3), priv: 15, status: :disabled)
      provider.fake_password = 'old'

      expect(changed_count(apply(user_id: 3, priv: 3))).to eq(1)
      expect(log).to eq([[:password, 3, 'secret'], [:grant, 3, 3]])
      expect(provider.fake_reads).to eq([[1]])
      expect(state(3)).to include(status: :enabled, priv: 3)
    end

    it 'reads the table again only to confirm a takeover, and keeps writing from what it knows' do
      FakeUserBmc.update(slot(3), name: 'SLAM')

      expect(changed_count(apply(user_id: 3, priv: 3))).to eq(1)
      expect(log).to eq([[:revoke, 3, [1]], [:name, 3, 'bob'], [:password, 3, 'secret'], [:grant, 3, 3]])
      expect(provider.fake_reads).to eq([[1], [1]])
    end

    it 'reads the table once to retire a user the BMC reports disabled with no privilege' do
      FakeUserBmc.update(slot(3), priv: 15, status: :disabled)

      expect(changed_count(apply(user_id: 3, ensure: :absent, password: nil))).to eq(1)
      expect(log).to eq([[:name, 3, 'DISABLED_3']])
      expect(provider.fake_reads).to eq([[1]])
    end

    it 'reads the table again to confirm a revoke before retiring a user the BMC does not report disabled' do
      FakeUserBmc.update(slot(3), status: :unknown)

      expect(changed_count(apply(user_id: 3, ensure: :absent, password: nil))).to eq(1)
      expect(log).to eq([[:revoke, 3, [1]], [:name, 3, 'DISABLED_3']])
      expect(provider.fake_reads).to eq([[1], [1]])
    end
  end

  describe 'purge_duplicates' do
    before do
      FakeUserBmc.update(slot(3), name: 'bob', priv: 4, status: :enabled)
      FakeUserBmc.update(slot(4), name: 'bob', priv: 4, status: :enabled)
      slot(1)[:name] = 'bob'
    end

    it 'blanks the duplicate, leaves the managed and anonymous slots alone, then stays quiet' do
      report = apply(user_id: 3, purge_duplicates: true)

      expect(state(4)).to include(name: 'DISABLED_4', status: :disabled, priv: 15)
      expect(slot(1)[:name]).to eq('bob')
      expect(state(3)).to include(name: 'bob', status: :enabled)
      expect(report.resource_statuses.keys).to include('Ipmi_user[bob (duplicate in slot 4)]')

      log.clear
      expect(changed_count(apply(user_id: 3, purge_duplicates: true))).to eq(0)
      expect(log).to be_empty
    end

    it 'purges the duplicate before the managed slot is named' do
      FakeUserBmc.update(slot(3), name: '', priv: 15, status: :disabled)
      apply(user_id: 3, purge_duplicates: true)

      expect(log.index([:name, 4, 'DISABLED_4'])).to be < log.index([:name, 3, 'bob'])
    end

    it 'reports the purge under noop and writes nothing' do
      Puppet[:noop] = true
      report = apply(user_id: 3, purge_duplicates: true)

      expect(log).to be_empty
      expect(report.resource_statuses['Ipmi_user[bob (duplicate in slot 4)]'].out_of_sync).to be(true)
    ensure
      Puppet[:noop] = false
    end

    it 'leaves duplicates alone unless asked' do
      apply(user_id: 3)

      expect(slot(4)[:name]).to eq('bob')
    end

    it 'keeps the lowest existing slot for user_id auto and purges the others' do
      apply(purge_duplicates: true)

      expect(slot(3)[:name]).to eq('bob')
      expect(slot(4)[:name]).to eq('DISABLED_4')
    end

    it 'purges a duplicate of a username managed on two channels, then stays quiet' do
      sets = [{ name: 'bob', purge_duplicates: true }, { name: 'bob-ch2', username: 'bob', channel: 2, purge_duplicates: true }]
      report = apply_all(*sets)

      expect(report.resource_statuses.values.count(&:failed)).to eq(0)
      expect(state(3)).to include(name: 'bob', status: :enabled)
      expect(slot(4)[:name]).to eq('DISABLED_4')

      log.clear
      expect(changed_count(apply_all(*sets))).to eq(0)
      expect(log).to be_empty
    end
  end
end
