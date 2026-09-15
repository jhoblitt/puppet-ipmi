# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_user'

# Runs real catalogs against the in-memory fake BMC to check that
# prefetch, ensure and the property setters cooperate and converge.
describe 'ipmi_user catalog application' do
  let(:type) { Puppet::Type.type(:ipmi_user) }
  let(:table) { FakeUserBmc.table_with({ id: 1 }, { id: 2, name: 'ADMIN', priv: 4, enabled: true }, { id: 3 }, { id: 4 }) }
  let(:log) { [] }
  let(:state_dir) { Dir.mktmpdir }

  let(:provider) { FakeUserBmc.registered_provider }

  before do
    Puppet[:statedir] = state_dir
    provider.stubs(:suitable?).returns(true)
    provider.fake_table = table
    provider.fake_log = log
    provider.fake_password = 'secret'
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

  it 'creates a user on the first run and is idempotent on the second' do
    expect(changed_count(apply(user_id: 3))).to eq(1)
    expect(table.find { |u| u[:id] == 3 }).to include(name: 'bob', priv: 4, enabled: true)

    log.clear
    expect(changed_count(apply(user_id: 3))).to eq(0)
    expect(log).to be_empty
  end

  it 'allocates the lowest free slot for user_id auto' do
    apply
    expect(table.find { |u| u[:id] == 3 }[:name]).to eq('bob')
  end

  it 'replaces an account occupying an explicitly selected slot' do
    report = apply(user_id: 2)

    expect(report.resource_statuses.values.count(&:failed)).to eq(0)
    expect(table.find { |u| u[:id] == 2 }).to include(name: 'bob', enabled: true, priv: 4)
    expect(log).to include([:name, 2, 'bob'], [:password, 2, 'secret'])

    log.clear
    expect(changed_count(apply(user_id: 2))).to eq(0)
    expect(log).to be_empty
  end

  it 'revokes access but does not rename an occupied slot for a different disabled username' do
    report = apply(user_id: 2, enable: :false, password: nil)

    expect(report.resource_statuses.values.count(&:failed)).to eq(0)
    expect(table.find { |u| u[:id] == 2 }).to include(name: 'ADMIN', enabled: false, priv: 15)
    expect(log).to include([:access, 2, false, 15])
    expect(log).not_to include([:name, 2, 'bob'])

    log.clear
    expect(changed_count(apply(user_id: 2, enable: :false, password: nil))).to eq(1)
    expect(table.find { |u| u[:id] == 2 }[:name]).to eq('ADMIN')
  end

  it 'converges a disabled user and then stays quiet' do
    expect(changed_count(apply(user_id: 3, enable: :false, password: nil))).to eq(1)
    expect(table.find { |u| u[:id] == 3 }).to include(name: 'bob', enabled: false, priv: 15)

    expect(changed_count(apply(user_id: 3, enable: :false, password: nil))).to eq(0)
  end

  it 'stays quiet for unfixable drift on an already disabled slot' do
    # Slot disabled out-of-band while holding a privilege; BMCs refuse
    # permission changes on disabled accounts, so this can never converge.
    table.find { |u| u[:id] == 3 }.merge!(name: 'bob', priv: 4, enabled: false)

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
    expect(table.find { |u| u[:id] == 2 }).to include(name: 'DISABLED_2', enabled: false)

    expect(changed_count(apply(name: 'ADMIN', user_id: 2, ensure: :absent, password: nil))).to eq(0)
    expect(changed_count(apply(name: 'ghost', ensure: :absent, password: nil))).to eq(0)
  end

  it 'gives the same slots to several auto resources regardless of catalog order' do
    sets = [{ name: 'zed' }, { name: 'amy' }, { name: 'bob' }]
    apply_all(*sets)
    first = table.map { |u| u[:name] }

    table.each { |u| u.merge!(name: '', priv: 15, enabled: false) unless u[:id] == 2 }
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

  describe 'purge_duplicates' do
    let(:slot) { ->(id) { table.find { |u| u[:id] == id } } }

    before do
      slot.call(3).merge!(name: 'bob', priv: 4, enabled: true)
      slot.call(4).merge!(name: 'bob', priv: 4, enabled: true)
      slot.call(1)[:name] = 'bob'
    end

    it 'blanks the duplicate, leaves the managed and anonymous slots alone, then stays quiet' do
      report = apply(user_id: 3, purge_duplicates: true)

      expect(slot.call(4)).to include(name: 'DISABLED_4', enabled: false, priv: 15)
      expect(slot.call(1)[:name]).to eq('bob')
      expect(slot.call(3)).to include(name: 'bob', enabled: true)
      expect(report.resource_statuses.keys).to include('Ipmi_user[bob (duplicate in slot 4)]')

      log.clear
      expect(changed_count(apply(user_id: 3, purge_duplicates: true))).to eq(0)
      expect(log).to be_empty
    end

    it 'purges the duplicate before the managed slot is named' do
      slot.call(3).merge!(name: '', priv: 15, enabled: false)
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

      expect(slot.call(4)[:name]).to eq('bob')
    end

    it 'keeps the lowest existing slot for user_id auto and purges the others' do
      apply(purge_duplicates: true)

      expect(slot.call(3)[:name]).to eq('bob')
      expect(slot.call(4)[:name]).to eq('DISABLED_4')
    end
  end
end
