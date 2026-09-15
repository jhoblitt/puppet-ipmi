# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/ipmi/provider/user_logic'

describe PuppetX::Ipmi::Provider::UserLogic do
  let(:table) do
    FakeUserBmc.table_with(
      { id: 1 },
      { id: 2, name: 'ADMIN', priv: 4, enabled: true },
      { id: 3 },
      { id: 4, name: 'DISABLED_4' }
    )
  end
  let(:log) { [] }
  let(:provider_class) { FakeUserBmc.provider_class(table, log, password: 'secret') }
  let(:params) do
    { name: 'bob', username: 'bob', password: 'secret', priv: 4, enable: :true, channel: 1, user_id: 3, purge_duplicates: false }
  end
  let(:provider) { provider_class.provider_for(params, provider_class.read_users(1)) }

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
    let(:channel) { 1 }

    it 'reports an absent user' do
      expect(described_class.property_hash_for(nil, channel)).to eq(ensure: :absent)
    end

    it 'reports an enabled, privileged user as present and enabled' do
      hash = described_class.property_hash_for({ id: 2, name: 'ADMIN', priv: 4, enabled: true }, channel)

      expect(hash).to eq(
        ensure: :present, name: 'ADMIN', user_id: 2, priv: 4, enable: :true, channel: 1
      )
    end

    it 'reports a named slot with NO ACCESS as disabled' do
      hash = described_class.property_hash_for({ id: 2, name: 'ADMIN', priv: 15, enabled: true }, channel)

      expect(hash[:enable]).to eq(:false)
    end

    it 'reports a named slot with no enabled flag as disabled' do
      hash = described_class.property_hash_for({ id: 2, name: 'ADMIN', priv: 4, enabled: false }, channel)

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

    it 'never matches the anonymous slot for :auto' do
      table[0][:name] = 'anon'
      expect(described_class.existing_slot(table, 'anon', :auto)).to be_nil
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

  describe '.prefetch' do
    it 'reads each channel once and binds a provider to every resource' do
      provider_class.expects(:read_users).with(1).once.returns(table)
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

      expect(log).to eq([[:access, 2, false, 15], [:name, 2, 'DISABLED_2']])
    end

    it 'destroy never adjusts permissions on an already disabled account' do
      table[1].merge!(enabled: false, priv: 4)
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      provider.destroy

      expect(log).to eq([[:name, 2, 'DISABLED_2']])
    end

    it 'destroy leaves a reserved, disabled user with no access untouched apart from the name' do
      table[2].merge!(name: 'bob', priv: 15, enabled: false)
      provider.destroy

      expect(log).to eq([[:name, 3, 'DISABLED_3']])
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

    it 'reports a named, privileged slot whose enabled flag is off as disabled and not revoked' do
      table[2].merge!(name: 'bob', priv: 4)
      expect(provider.enable).to eq(:false)
      expect(provider).not_to be_access_revoked
    end

    it 'treats unfixable drift on an already disabled slot as converged, with a note' do
      params[:enable] = :false
      table[2].merge!(name: 'bob', priv: 4)
      Puppet.expects(:info).with(regexp_matches(%r{disabled with priv 4}))

      expect(provider.enable).to eq(:false)
      expect(provider).to be_access_revoked
    end

    it 'reads the table once per run' do
      provider_class.expects(:read_users).once.returns(table)
      p = provider_class.provider_for(params, provider_class.read_users(1))
      p.priv
      p.enable
      p.exists?
    end
  end

  describe '#create' do
    it 'names the slot, sets the password and grants access in order' do
      provider.create

      expect(log).to eq([[:name, 3, 'bob'], [:password, 3, 'secret'], [:access, 3, true, 4]])
    end

    it 'skips the name write when the slot already holds the username' do
      table[2][:name] = 'bob'
      provider.create

      expect(log).to eq([[:password, 3, 'secret'], [:access, 3, true, 4]])
    end

    it 'skips the password when none is given' do
      params[:password] = nil
      provider.create

      expect(log.map(&:first)).to eq(%i[name access])
    end

    it 'unwraps Sensitive passwords' do
      params[:password] = Puppet::Pops::Types::PSensitiveType::Sensitive.new('wrapped')
      provider.create

      expect(log).to include([:password, 3, 'wrapped'])
    end

    it 'reserves the name and revokes access when the resource is disabled' do
      params[:enable] = :false
      provider.create

      expect(log).to eq([[:name, 3, 'bob'], [:access, 3, false, 15]])
    end
  end

  describe '#enable=' do
    it 'does not rename a named slot when disabling' do
      params[:user_id] = 2
      params[:username] = 'ADMIN'
      provider.enable = :false

      expect(log).to eq([[:access, 2, false, 15]])
    end

    it 'never adjusts permissions on an already disabled slot when disabling' do
      table[2].merge!(name: 'bob', priv: 4, enabled: false)
      Puppet.expects(:info).with(regexp_matches(%r{already disabled}))

      provider.enable = :false

      expect(log).to be_empty
    end

    it 'still writes access when the slot is enabled' do
      table[2].merge!(name: 'bob', priv: 4, enabled: true)
      provider.enable = :false

      expect(log).to eq([[:access, 3, false, 15]])
    end

    it 'grants access when enabling' do
      table[2][:name] = 'bob'
      provider.enable = :true

      expect(log.last).to eq([:access, 3, true, 4])
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
    it 'writes the privilege of an owned slot' do
      table[2][:name] = 'bob'
      provider.priv = 3

      expect(log).to eq([[:priv, 3, 3]])
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
    let(:holder) do
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
