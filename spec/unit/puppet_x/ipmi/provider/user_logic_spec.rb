# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/ipmi/provider/user_logic'

describe PuppetX::Ipmi::Provider::UserLogic do
  let(:table) do
    FakeUserBmc.table_with(
      { id: 1 },
      { id: 2, name: 'ADMIN', priv: 4, status: :enabled },
      { id: 3 },
      { id: 4, name: 'DISABLED_4' },
    )
  end
  let(:log) { [] }
  let(:provider_class) { FakeUserBmc.provider_class(table, log, password: 'secret') }
  let(:params) do
    { name: 'bob', username: 'bob', password: 'secret', priv: 4, enable: :true, channel: 1, user_id: 3, purge_duplicates: false }
  end
  let(:provider) { provider_class.provider_for(params, provider_class.read_table([1])) }

  describe '.free_name?' do
    it 'treats an empty name as free' do
      expect(described_class.free_name?('')).to be(true)
    end

    it 'treats a DISABLED_ placeholder as free' do
      expect(described_class.free_name?('DISABLED_7')).to be(true)
    end

    it 'treats any other name as occupied' do
      expect(described_class.free_name?('ADMIN')).to be(false)
      expect(described_class.free_name?('disable_me')).to be(false)
    end
  end

  describe '.disabled_name' do
    it 'formats the placeholder given to a purged slot' do
      expect(described_class.disabled_name(7)).to eq('DISABLED_7')
    end
  end

  describe '.property_hash_for' do
    it 'reports an absent user' do
      expect(described_class.property_hash_for(nil, 1)).to eq(ensure: :absent)
    end

    it 'reports an enabled, privileged user as present and enabled' do
      hash = described_class.property_hash_for({ id: 2, name: 'ADMIN', status: :enabled, privs: { 1 => 4 } }, 1)

      expect(hash).to eq(
        ensure: :present, name: 'ADMIN', user_id: 2, priv: 4, enable: :true, channel: 1,
      )
    end

    it 'reports a named slot with NO ACCESS as disabled' do
      hash = described_class.property_hash_for({ id: 2, name: 'ADMIN', status: :enabled, privs: { 1 => 15 } }, 1)

      expect(hash[:enable]).to eq(:false)
    end

    it 'reports a named slot with no enabled flag as disabled' do
      hash = described_class.property_hash_for({ id: 2, name: 'ADMIN', status: :disabled, privs: { 1 => 4 } }, 1)

      expect(hash[:enable]).to eq(:false)
    end
  end

  describe '.existing_slot' do
    it 'matches an explicit id only when the slot holds the username' do
      expect(described_class.existing_slot(table, 'ADMIN', 2)).to include(id: 2)
      expect(described_class.existing_slot(table, 'ADMIN', 3)).to be_nil
    end

    it 'matches the lowest id holding the username for :auto' do
      table[2][:name] = 'ADMIN'
      expect(described_class.existing_slot(table, 'ADMIN', :auto)[:id]).to eq(2)
    end

    it 'skips the given ids for :auto' do
      table[2][:name] = 'ADMIN'
      expect(described_class.existing_slot(table, 'ADMIN', :auto, skip: [2])[:id]).to eq(3)
    end

    it 'never matches the anonymous slot for :auto' do
      table[0][:name] = 'anon'
      expect(described_class.existing_slot(table, 'anon', :auto)).to be_nil
    end
  end

  describe '.merge' do
    it 'reports no privilege on a channel whose list lacks the slot' do
      lists = { 1 => [{ id: 2, name: 'ADMIN', priv: 4 }, { id: 3, name: 'bob', priv: 2 }], 2 => [{ id: 2, name: 'ADMIN', priv: 3 }] }
      merged = described_class.merge(lists, { 2 => :enabled })

      expect(merged).to eq(
        [
          { id: 2, name: 'ADMIN', status: :enabled, privs: { 1 => 4, 2 => 3 } },
          { id: 3, name: 'bob', status: :unknown, privs: { 1 => 2, 2 => nil } },
        ],
      )
    end
  end

  describe '.instances' do
    it 'returns one provider per named slot, skipping empty and DISABLED_ slots' do
      Facter.stubs(:value).with('ipmi.default.channel').returns(nil)
      instances = provider_class.instances

      expect(instances.map(&:name)).to eq(['ADMIN'])
      expect(instances.first.priv).to eq(4)
      expect(instances.first.enable).to eq(:true)
      expect(instances.first).to be_exists
    end
  end

  describe 'the table cache' do
    after { described_class::TableCache.clear }

    # Read a table through the cache, recording in `reads` each channel
    # read from the BMC.
    def read(reads, catalog, channel = 1)
      described_class::TableCache.read(catalog, [provider_class, channel]) do
        reads << channel
        []
      end
    end

    it 'reads once per catalog, provider and channel' do
      reads = []
      catalog = Puppet::Resource::Catalog.new
      2.times { read(reads, catalog) }
      read(reads, catalog, 2)

      expect(reads).to eq([1, 2])
    end

    it 'reads again for another catalog' do
      reads = []
      read(reads, Puppet::Resource::Catalog.new)
      read(reads, Puppet::Resource::Catalog.new)

      expect(reads).to eq([1, 1])
    end

    it 'reads every time without a catalog' do
      reads = []
      2.times { read(reads, nil) }

      expect(reads).to eq([1, 1])
    end

    it 'reads again after a write' do
      reads = []
      catalog = Puppet::Resource::Catalog.new
      read(reads, catalog)
      provider.refresh_slots!
      read(reads, catalog)

      expect(reads).to eq([1, 1])
    end

    it 'reads again after the transaction' do
      reads = []
      catalog = Puppet::Resource::Catalog.new
      read(reads, catalog)
      provider_class.post_resource_eval
      read(reads, catalog)

      expect(reads).to eq([1, 1])
    end

    it 'probes the LAN channels once per transaction, even across writes' do
      probes = []
      catalog = Puppet::Resource::Catalog.new
      probe = lambda do
        described_class::TableCache.lan_channels(catalog, provider_class) do
          probes << :probe
          [1]
        end
      end
      probe.call
      provider.refresh_slots!
      probe.call
      provider_class.post_resource_eval
      probe.call

      expect(probes).to eq(%i[probe probe])
    end
  end

  describe '.prefetch' do
    it 'reads each channel once and binds a provider to every resource' do
      provider_class.expects(:read_table).with([1]).once.returns(table)
      a = Struct.new(:data, :provider) do
        def [](key)
          data[key]
        end
      end
      one = a.new(params.merge(user_id: 2, username: 'ADMIN'))
      two = a.new(params.merge(name: 'amy', username: 'amy', user_id: 3))

      provider_class.prefetch('ADMIN' => one, 'amy' => two)

      expect(one.provider).to be_exists
      expect(two.provider).not_to be_exists
    end
  end

  describe 'ensure' do
    it 'exists when the slot holds the username' do
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      expect(provider).to be_exists
    end

    it 'does not exist when the explicit slot holds another name' do
      params[:user_id] = 2
      expect(provider).not_to be_exists
    end

    it 'exists for :auto when any slot holds the username' do
      table[2][:name] = 'bob'
      params[:user_id] = :auto
      expect(provider).to be_exists
    end

    it 'does not exist for :auto when the slot holding the username is allocated elsewhere' do
      table[2][:name] = 'bob'
      params[:user_id] = :auto
      allocation = { id: 4 }
      p = provider_class.provider_for(params, provider_class.read_table([1]), allocation)

      expect(p).not_to be_exists
      expect(p.resolved_user_id).to eq(4)
    end

    it 'does not allocate a slot for an absent :auto user' do
      params[:user_id] = :auto
      params[:ensure] = :absent
      expect(provider).not_to be_exists
      expect(provider.resolved_user_id).to be_nil
    end

    it 'destroy revokes access first, then blanks the slot' do
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      provider.destroy

      expect(log).to eq([[:revoke, 2, [1]], [:name, 2, 'DISABLED_2']])
    end

    it 'destroy lets the backend tolerate refusals on an account the BMC reports disabled, but does not retire it while a channel grants it a privilege' do
      FakeUserBmc.update(table[1], status: :disabled, priv: 15, privs: { 2 => 4 })
      provider_class.fake_lan_channels = [1, 2]
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      provider_class.expects(:revoke_access).with([1, 2], 2, already_disabled: true)
      p = provider_class.provider_for(params, provider_class.read_table([1, 2]))

      expect { p.destroy }.to raise_error(Puppet::Error, 'Refusing to rename slot 2: the BMC did not revoke its access, it still has priv 4 on channel 2')
      expect(log).to be_empty
    end

    it 'destroy does not retire a slot when the read confirming its revoke misses a channel it revoked' do
      FakeUserBmc.update(table[1], status: :unknown, priv: 15)
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      p = provider_class.provider_for(params, provider_class.read_table([1, 2]))

      expect { p.destroy }.to raise_error(Puppet::Error, %r{Refusing to rename slot 2: .*priv unread on channel 2})
      expect(log).to eq([[:revoke, 2, [1, 2]]])
    end

    it 'destroy does not retire a slot that the BMC no longer lists, since its revoke cannot be confirmed' do
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      target = provider
      provider_class.fake_table = table.reject { |u| u[:id] == 2 }
      provider_class.stubs(:revoke_access)
      target.slots = []

      expect { target.destroy }.to raise_error(Puppet::Error, %r{Refusing to rename slot 2: it is missing from the BMC's user table})
      expect(log).to be_empty
    end

    it 'reads its own table when it has no prefetched snapshot' do
      bare = provider_class.new(ensure: :absent)
      bare.resource = params
      bare.refresh_slots!

      expect(bare.slots.map { |u| u[:id] }).to eq([1, 2, 3, 4])
    end

    it 'records a write without a snapshot as nothing to update' do
      bare = provider_class.new(ensure: :absent)
      bare.resource = params
      yielded = false
      bare.send(:wrote, 3) { yielded = true }

      expect(yielded).to be(false)
    end

    it 'destroy leaves a reserved, disabled user with no access untouched apart from the name' do
      FakeUserBmc.update(table[2], name: 'bob', priv: 15, status: :disabled)
      provider.destroy

      expect(log).to eq([[:name, 3, 'DISABLED_3']])
    end

    it 'destroy revokes an account it cannot verify is disabled, letting the backend tolerate refused permission changes' do
      FakeUserBmc.update(table[1], status: :unknown, priv: 15)
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      provider_class.expects(:revoke_access).with([1], 2, already_disabled: true)
      provider.destroy

      expect(log).to eq([[:name, 2, 'DISABLED_2']])
    end

    it 'destroy revokes an enabled account that has NO ACCESS on this channel' do
      FakeUserBmc.update(table[1], status: :enabled, priv: 15)
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      provider.destroy

      expect(log).to eq([[:revoke, 2, [1]], [:name, 2, 'DISABLED_2']])
    end

    it 'disabling re-reads a cached table that lacks the slot, so an unprivileged slot is only named' do
      params[:enable] = :false
      provider.slots = table.reject { |u| u[:id] == 3 }
      provider.create

      expect(log).to eq([[:name, 3, 'bob']])
    end

    it 'destroy leaves the slot free for reallocation' do
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      provider.destroy

      expect(described_class.free_name?(table[1][:name])).to be(true)
    end
  end

  describe 'getters' do
    it 'reports privilege and enable from the prefetched entry' do
      params[:user_id] = 2
      params[:username] = 'ADMIN'

      expect(provider.priv).to eq(4)
      expect(provider.enable).to eq(:true)
    end

    it 'reports a named slot without access as disabled' do
      table[2][:name] = 'bob'
      expect(provider.enable).to eq(:false)
      expect(provider).to be_access_revoked
    end

    it 'does not report access revoked when the table has no such slot' do
      params[:enable] = :false
      provider.slots = []

      expect(provider).not_to be_access_revoked
    end

    it 'does not report access revoked for an enabled account with NO ACCESS on this channel' do
      params[:enable] = :false
      FakeUserBmc.update(table[2], name: 'bob', priv: 15, status: :enabled)

      expect(provider.enable).to eq(:false)
      expect(provider).not_to be_access_revoked
    end

    it 'does not report access revoked for a slot of unknown status that has a privilege on another channel' do
      params[:enable] = :false
      FakeUserBmc.update(table[2], name: 'bob', status: :unknown, privs: { 2 => 4 })
      p = provider_class.provider_for(params, provider_class.read_table([1, 2]))

      expect(p.enable).to eq(:false)
      expect(p).not_to be_access_revoked
    end

    it 'reports access revoked for a slot of unknown status that no channel grants a privilege' do
      params[:enable] = :false
      FakeUserBmc.update(table[2], name: 'bob', status: :unknown)
      p = provider_class.provider_for(params, provider_class.read_table([1, 2]))

      expect(p).to be_access_revoked
    end

    it 'treats unfixable drift on an already disabled slot as converged, with a note' do
      params[:enable] = :false
      FakeUserBmc.update(table[2], name: 'bob', priv: 4)
      Puppet.expects(:info).with(regexp_matches(%r{disabled with priv 4}))

      expect(provider.enable).to eq(:false)
      expect(provider).to be_access_revoked
    end

    it 'reads the table once per run' do
      provider_class.expects(:read_table).once.returns(table)
      p = provider_class.provider_for(params, provider_class.read_table([1]))
      p.priv
      p.enable
      p.exists?
    end
  end

  describe '#create' do
    it 'names the slot, sets the password and grants access in order' do
      provider.create

      expect(log).to eq([[:name, 3, 'bob'], [:password, 3, 'secret'], [:grant, 3, 4]])
    end

    it 'skips the name write when the slot already holds the username' do
      table[2][:name] = 'bob'
      provider.create

      expect(log).to eq([[:password, 3, 'secret'], [:grant, 3, 4]])
    end

    it 'names the slot when it is missing from the cached table' do
      provider.slots = table.reject { |u| u[:id] == 3 }
      provider.create

      expect(log.first).to eq([:name, 3, 'bob'])
    end

    it 'skips the password when none is given' do
      params[:password] = nil
      provider.create

      expect(log.map(&:first)).to eq(%i[name grant])
    end

    it 'unwraps Sensitive passwords' do
      params[:password] = Puppet::Pops::Types::PSensitiveType::Sensitive.new('wrapped')
      provider.create

      expect(log).to include([:password, 3, 'wrapped'])
    end

    it 'reserves the name of a slot the BMC reports disabled with no privilege, writing nothing else' do
      params[:enable] = :false
      provider.create

      expect(log).to eq([[:name, 3, 'bob']])
    end

    it 'revokes a slot of unknown status before reserving its name when the resource is disabled' do
      params[:enable] = :false
      FakeUserBmc.update(table[2], status: :unknown)
      provider.create

      expect(log).to eq([[:revoke, 3, [1]], [:name, 3, 'bob']])
    end

    it 'takes over an explicit slot held by another user when the resource is disabled, revoking before renaming' do
      params.merge!(enable: :false, user_id: 2)
      provider.create

      expect(log).to eq([[:revoke, 2, [1]], [:name, 2, 'bob']])
    end

    it 'lets the backend tolerate refused permission changes on an account not reported enabled, but does not rename it while it has a privilege' do
      params[:enable] = :false
      FakeUserBmc.update(table[2], status: :unknown, priv: 4)
      provider_class.expects(:revoke_access).with([1], 3, already_disabled: true)

      expect { provider.create }.to raise_error(Puppet::Error, %r{Refusing to rename slot 3: .*priv 4 on channel 1})
      expect(log).to be_empty
    end

    it 'renames an account not reported enabled once a fresh read finds that no channel grants it a privilege' do
      params[:enable] = :false
      FakeUserBmc.update(table[2], status: :unknown, priv: 4)
      provider.create

      expect(log).to eq([[:revoke, 3, [1]], [:name, 3, 'bob']])
    end

    it 'does not let the backend tolerate refused permission changes when revoking an enabled account' do
      params.merge!(enable: :false, user_id: 2)
      provider_class.expects(:revoke_access).with([1], 2, already_disabled: false)
      provider.create
    end

    describe 'taking over a slot that holds another, enabled account' do
      before { params[:user_id] = 2 }

      it 'revokes and disables it, then renames the slot, sets the password and enables it' do
        provider.create

        expect(log).to eq([[:revoke, 2, [1]], [:name, 2, 'bob'], [:password, 2, 'secret'], [:grant, 2, 4]])
      end

      it 'writes nothing when the backend cannot carry the password' do
        provider_class.stubs(:check_password).with(1, 2, 'secret').raises(Puppet::Error, 'cannot carry it')

        expect { provider.create }.to raise_error(Puppet::Error, 'cannot carry it')
        expect(log).to be_empty
      end

      it 'writes nothing when the backend cannot carry the username' do
        provider_class.stubs(:check_name).with(1, 2, 'bob').raises(Puppet::Error, 'cannot carry it')

        expect { provider.create }.to raise_error(Puppet::Error, 'cannot carry it')
        expect(log).to be_empty
      end

      it 'does not rename the slot when revoking the old account fails' do
        provider_class.stubs(:revoke_access).raises(Puppet::ExecutionFailure, 'revoke failed')

        expect { provider.create }.to raise_error(Puppet::ExecutionFailure, 'revoke failed')
        expect(log).to be_empty
        expect(table[1][:name]).to eq('ADMIN')
      end

      it 'leaves the renamed slot disabled when the password write fails' do
        provider_class.stubs(:write_password).raises(Puppet::ExecutionFailure, 'password failed')

        expect { provider.create }.to raise_error(Puppet::ExecutionFailure, 'password failed')
        expect(log).to eq([[:revoke, 2, [1]], [:name, 2, 'bob']])
        expect(FakeUserBmc.view(table[1])).to include(name: 'bob', status: :disabled, priv: 15)
      end
    end
  end

  describe '#enable=' do
    it 'does not rename a named slot when disabling' do
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      provider.enable = :false

      expect(log).to eq([[:revoke, 2, [1]]])
    end

    it 'revokes a slot the BMC reports disabled that still has a privilege, letting the backend tolerate refusals' do
      FakeUserBmc.update(table[2], name: 'bob', priv: 4, status: :disabled)
      provider_class.expects(:revoke_access).with([1], 3, already_disabled: true)

      provider.enable = :false
    end

    it 'still writes access when the slot is enabled' do
      FakeUserBmc.update(table[2], name: 'bob', priv: 4, status: :enabled)
      provider.enable = :false

      expect(log).to eq([[:revoke, 3, [1]]])
    end

    it 'grants access when enabling' do
      table[2][:name] = 'bob'
      provider.enable = :true

      expect(log.last).to eq([:grant, 3, 4])
    end
  end

  describe 'password' do
    it 'reports :absent' do
      expect(provider.password).to eq(:absent)
    end

    it 'is in sync when the backend confirms the password' do
      expect(provider.password_insync?).to be(true)
    end

    it 'is out of sync when the backend rejects the password' do
      params[:password] = 'other'
      expect(provider.password_insync?).to be(false)
    end

    it 'is out of sync, not an exception, when the check raises' do
      provider_class.stubs(:password_matches?).raises(Puppet::ExecutionFailure, 'boom')
      expect(provider.password_insync?).to be(false)
    end

    it 'warns when the check raises, so the churn is visible' do
      provider_class.stubs(:password_matches?).raises(Puppet::ExecutionFailure, 'boom')
      Puppet.expects(:warning).with(regexp_matches(%r{password check failed}))

      expect(provider.password_insync?).to be(false)
    end

    it 'is in sync when disabling' do
      params[:enable] = :false
      params[:password] = 'other'
      expect(provider.password_insync?).to be(true)
    end

    [nil, ''].each do |empty|
      it "is in sync, without asking the BMC, when the password is #{empty.inspect}" do
        params[:password] = empty
        provider_class.expects(:password_matches?).never

        expect(provider.password_insync?).to be(true)
      end

      it "does not write when the password is #{empty.inspect}" do
        params[:password] = empty
        provider.password = :ignored

        expect(log).to be_empty
      end
    end

    it 'reports the missing slot when the resolved slot is not in the table' do
      table[2][:name] = 'bob'
      provider.slots = table.reject { |u| u[:id] == 3 }

      expect { provider.password = :ignored }.to raise_error(Puppet::Error, %r{slot contains nil})
    end

    it 'writes the password once the slot is owned' do
      table[2][:name] = 'bob'
      provider.password = :ignored

      expect(log).to eq([[:password, 3, 'secret']])
    end

    it 'refuses to write to a slot owned by another user' do
      params[:user_id] = 2

      expect { provider.password = :ignored }.to raise_error(Puppet::Error, %r{Refusing to modify slot 2})
      expect(log).to be_empty
    end

    it 'does not write when disabling' do
      params[:enable] = :false
      provider.password = :ignored

      expect(log).to be_empty
    end
  end

  describe 'priv=' do
    it 'writes the privilege of an owned, enabled slot' do
      FakeUserBmc.update(table[2], name: 'bob', priv: 4, status: :enabled)
      provider.priv = 3

      expect(log).to eq([[:priv, 3, 3]])
    end

    it 'leaves the privilege to enable= when the run enables a disabled slot' do
      FakeUserBmc.update(table[2], name: 'bob', priv: 15, status: :disabled)
      provider.priv = 4

      expect(log).to be_empty
    end

    it 'refuses to change the privilege of a slot owned by another user' do
      params[:user_id] = 2

      expect { provider.priv = 3 }.to raise_error(Puppet::Error, %r{Refusing to modify slot 2})
    end
  end

  describe '.stray_slots' do
    before do
      table[0][:name] = 'bob'
      table[1][:name] = 'bob'
      table[2][:name] = 'bob'
    end

    it 'reports every slot with the username that no resource claims' do
      expect(described_class.stray_slots(table, 'bob', [3]).map { |u| u[:id] }).to eq([2])
    end

    it 'never reports the anonymous slot' do
      expect(described_class.stray_slots(table, 'bob', []).map { |u| u[:id] }).to eq([2, 3])
    end

    it 'ignores slots claimed by other resources' do
      expect(described_class.stray_slots(table, 'bob', [2, 3])).to be_empty
    end

    it 'ignores other usernames' do
      expect(described_class.stray_slots(table, 'amy', [])).to be_empty
    end
  end

  describe '.stray_slots on the provider class' do
    def holder
      Struct.new(:data) do
        def [](key)
          data[key]
        end
      end
    end

    before do
      table[0][:name] = 'bob'
      table[1][:name] = 'bob'
    end

    it 'treats the canonical slot of the resource as claimed' do
      bob = holder.new(params.merge(user_id: 3, ensure: :present))
      table[2][:name] = 'bob'

      expect(provider_class.stray_slots(bob, [bob]).map { |u| u[:id] }).to eq([2])
    end

    it 'keeps an existing auto slot and reports the others' do
      bob = holder.new(params.merge(user_id: :auto))
      table[2][:name] = 'bob'

      expect(provider_class.stray_slots(bob, [bob]).map { |u| u[:id] }).to eq([3])
    end

    it 'skips slots another catalog resource claims explicitly' do
      bob = holder.new(params.merge(user_id: 3))
      other = holder.new(params.merge(name: 'other', username: 'other', user_id: 2))

      expect(provider_class.stray_slots(bob, [bob, other])).to be_empty
    end

    it 'reports nothing when the resource cannot get a slot' do
      table.each { |u| u[:name] = "user#{u[:id]}" }
      bob = holder.new(params.merge(user_id: :auto))

      expect(provider_class.stray_slots(bob, [bob])).to be_empty
    end
  end

  describe 'user_id => auto' do
    before { params[:user_id] = :auto }

    it 'reuses the slot of an existing user with the same name' do
      table[1][:name] = 'bob'
      expect(provider.resolved_user_id).to eq(2)
    end

    it 'selects the lowest free slot, skipping slot 1 and treating DISABLED_* as free' do
      table[2][:name] = 'taken'
      expect(provider.resolved_user_id).to eq(4)
    end

    it 'never selects slot 1 even when it holds the requested name' do
      table[0][:name] = 'bob'
      expect(provider.resolved_user_id).to eq(3)
    end

    it 'raises when no free slot is available' do
      table.each { |u| u[:name] = "user#{u[:id]}" }
      expect { provider.resolved_user_id }.to raise_error(Puppet::Error, %r{No free IPMI user slot})
    end

    it 'allocates distinct ids to multiple auto resources during prefetch' do
      holder = Struct.new(:data, :provider) do
        def [](key)
          data[key]
        end
      end
      bob = holder.new(params)
      amy = holder.new(params.merge(name: 'amy', username: 'amy'))

      provider_class.prefetch('bob' => bob, 'amy' => amy)

      expect([amy.provider.resolved_user_id, bob.provider.resolved_user_id]).to eq([3, 4])
    end

    it 'allocates once across channels, reading each channel once' do
      holder = Struct.new(:data, :provider) do
        def [](key)
          data[key]
        end
      end
      provider_class.expects(:read_table).with([1, 2]).once.returns(table)
      alice = holder.new(params.merge(name: 'alice', username: 'alice', channel: 2))
      bob = holder.new(params)

      provider_class.prefetch('alice' => alice, 'bob' => bob)

      expect([alice.provider.resolved_user_id, bob.provider.resolved_user_id]).to eq([3, 4])
    end

    it 'fails only the resource that finds no free slot' do
      holder = Struct.new(:data, :provider) do
        def [](key)
          data[key]
        end
      end
      table[1][:name] = 'taken'
      resources = %w[a b c].to_h { |n| [n, holder.new(params.merge(name: n, username: n))] }

      provider_class.prefetch(resources)

      expect(resources['a'].provider.resolved_user_id).to eq(3)
      expect(resources['b'].provider.resolved_user_id).to eq(4)
      expect { resources['c'].provider.resolved_user_id }.to raise_error(Puppet::Error, %r{No free IPMI user slot})
    end
  end
end
