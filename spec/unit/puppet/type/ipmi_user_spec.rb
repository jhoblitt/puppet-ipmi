# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_user'
require 'tempfile'
require 'fileutils'

describe Puppet::Type.type(:ipmi_user) do
  describe 'when validating attributes' do
    %i[name username user_id channel purge_duplicates].each do |param|
      it "has a #{param} parameter" do
        expect(described_class.attrtype(param)).to eq(:param)
      end
    end

    %i[ensure password enable priv].each do |prop|
      it "has a #{prop} property" do
        expect(described_class.attrtype(prop)).to eq(:property)
      end
    end
  end

  describe 'when validating values' do
    ['0', '16', 'x', '', "1\nx", "1\n"].each do |bad|
      it "rejects channel #{bad.inspect}" do
        expect { described_class.new(name: 'test', enable: :false, channel: bad) }
          .to raise_error(Puppet::Error, %r{channel must be an integer})
      end
    end

    it 'accepts channels 1 and 15' do
      [1, 15].each do |ch|
        expect(described_class.new(name: "t#{ch}", enable: :false, channel: ch)[:channel]).to eq(ch)
      end
    end

    it 'rejects a user_id with a trailing newline' do
      expect { described_class.new(name: 'test', enable: :false, user_id: "3\nx") }
        .to raise_error(Puppet::Error, %r{user_id})
    end

    it 'rejects an empty username' do
      expect { described_class.new(name: 'test', enable: :false, username: '') }
        .to raise_error(Puppet::Error, %r{non-empty})
    end

    it 'rejects a username containing whitespace' do
      expect { described_class.new(name: 'test', enable: :false, username: 'a b') }
        .to raise_error(Puppet::Error, %r{whitespace})
    end

    it 'treats the password as in sync when none is declared' do
      resource = described_class.new(name: 'test', enable: :false, provider: :ipmitool)
      provider = resource.provider
      provider.expects(:password_insync?).never

      expect(resource.parameter(:password)).to be_nil
      property = described_class.attrclass(:password).new(resource: resource)
      expect(property.insync?(:absent)).to be(true)
    end

    it 'defaults username to the resource title' do
      resource = described_class.new(name: 'test', enable: :false)
      expect(resource[:username]).to eq('test')
    end

    it 'defaults user_id to auto' do
      resource = described_class.new(name: 'test', enable: :false)
      expect(resource[:user_id]).to eq(:auto)
    end

    it 'defaults channel to 1' do
      Facter.stubs(:value).with('ipmi.default.channel').returns(nil)
      resource = described_class.new(name: 'test', enable: :false)
      expect(resource[:channel]).to eq(1)
    end

    it 'does not read compiler-local facts for the channel default' do
      Facter.expects(:value).with('ipmi.default.channel').never
      resource = described_class.new(name: 'test', enable: :false)
      expect(resource[:channel]).to eq(1)
    end

    it 'accepts an explicitly supplied channel' do
      resource = described_class.new(name: 'test', enable: :false, channel: 3)
      expect(resource[:channel]).to eq(3)
    end

    it 'munges a channel given as a string to an Integer' do
      expect(described_class.new(name: 'test', enable: :false, channel: '15')[:channel]).to eq(15)
    end

    [0, 16, 'one', ''].each do |bad|
      it "rejects channel #{bad.inspect}" do
        expect { described_class.new(name: 'test', enable: :false, channel: bad) }
          .to raise_error(Puppet::Error, %r{channel must be an integer between 1 and 15})
      end
    end

    it 'defaults enable to true' do
      # enable defaults to true but requires password
      resource = described_class.new(name: 'test', password: 'secret')
      expect(resource[:enable]).to eq(:true)
    end

    it 'defaults priv to 4' do
      resource = described_class.new(name: 'test', password: 'secret')
      expect(resource[:priv]).to eq(4)
    end

    it 'rejects password over 20 characters when enable is true' do
      expect do
        described_class.new(name: 'test', password: 'a' * 21, enable: :true)
      end.to raise_error(Puppet::Error, %r{20 or fewer bytes})
    end

    it 'requires password when enable is true' do
      expect do
        described_class.new(name: 'test', enable: :true)
      end.to raise_error(Puppet::Error, %r{You must supply a password})
    end

    it 'rejects an empty plain password when enable is true' do
      expect do
        described_class.new(name: 'test', enable: :true, password: '')
      end.to raise_error(Puppet::Error, %r{You must supply a password})
    end

    it 'rejects an empty Sensitive password when enable is true' do
      expect do
        described_class.new(name: 'test', enable: :true, password: Puppet::Pops::Types::PSensitiveType::Sensitive.new(''))
      end.to raise_error(Puppet::Error, %r{You must supply a password})
    end

    it 'rejects a Sensitive password over 20 characters when enable is true' do
      expect do
        described_class.new(name: 'test', enable: :true, password: Puppet::Pops::Types::PSensitiveType::Sensitive.new('a' * 21))
      end.to raise_error(Puppet::Error, %r{20 or fewer bytes})
    end

    it 'rejects passwords that exceed 20 bytes even when shorter in characters' do
      expect do
        described_class.new(name: 'test', password: 'é' * 11)
      end.to raise_error(Puppet::Error, %r{20 or fewer bytes})
    end

    it 'rejects non-string passwords without leaking their value' do
      expect do
        described_class.new(name: 'test', password: 1234)
      end.to raise_error(Puppet::Error, %r{password must be a String})
    end

    it 'rejects non-string Sensitive passwords' do
      expect do
        described_class.new(name: 'test', password: Puppet::Pops::Types::PSensitiveType::Sensitive.new(1234))
      end.to raise_error(Puppet::Error, %r{password must be a String})
    end

    it 'rejects a username exceeding 16 bytes' do
      expect do
        described_class.new(name: 'test', username: 'é' * 9, enable: :false)
      end.to raise_error(Puppet::Error, %r{16 bytes})
    end

    # ipmitool's getopt would take such a name, on its command line, as an
    # option of its own.
    ['-v', '-Hhost'].each do |name|
      it "rejects the username #{name}, which starts with -" do
        expect do
          described_class.new(name: 'test', username: name, enable: :false)
        end.to raise_error(Puppet::Error, %r{username must not start with -})
      end

      it "rejects the title #{name} as the username" do
        expect do
          described_class.new(name: name, enable: :false)
        end.to raise_error(Puppet::Error, %r{username must not start with -})
      end
    end

    it 'accepts a username with - after its first character' do
      expect(described_class.new(name: 'test', username: 'a-v', enable: :false)[:username]).to eq('a-v')
    end

    it 'still rejects an over-long password when enable is false' do
      expect do
        described_class.new(name: 'test', enable: :false, password: 'a' * 21)
      end.to raise_error(Puppet::Error, %r{20 or fewer bytes})
    end

    it 'does not require password when enable is false' do
      resource = described_class.new(name: 'test', enable: :false)
      expect(resource[:enable]).to eq(:false)
    end

    it 'rejects invalid priv values when enable is true' do
      expect do
        described_class.new(name: 'test', password: 'secret', priv: 5)
      end.to raise_error(Puppet::Error, %r{priv must be})
    end

    it 'rejects invalid priv values when enable is false' do
      expect do
        described_class.new(name: 'test', enable: :false, priv: 5)
      end.to raise_error(Puppet::Error, %r{priv must be})
    end

    it 'ignores invalid priv values when ensure is absent' do
      expect { described_class.new(name: 'test', ensure: :absent, priv: 5) }.not_to raise_error
    end

    it 'accepts valid priv values' do
      [1, 2, 3, 4].each do |p|
        resource = described_class.new(name: "test#{p}", password: 'secret', priv: p)
        expect(resource[:priv]).to eq(p)
      end
    end

    it 'ignores priv mismatch when enable is false' do
      resource = described_class.new(name: 'test', enable: :false, priv: 3)
      expect(resource.property(:priv).insync?(4)).to be(true)
    end

    it 'defaults ensure to present' do
      resource = described_class.new(name: 'test', enable: :false)
      expect(resource[:ensure]).to eq(:present)
    end

    it 'does not require a password when ensure is absent' do
      expect { described_class.new(name: 'test', ensure: :absent) }.not_to raise_error
    end

    it 'treats a disabled user as in sync only once access is revoked' do
      resource = described_class.new(name: 'test', enable: :false, provider: :ipmitool)
      provider = resource.provider
      provider.stubs(:access_revoked?).returns(false, true)

      expect(resource.property(:enable).insync?(:false)).to be(false)
      expect(resource.property(:enable).insync?(:false)).to be(true)
    end

    it 'compares the enabled flag when enabling' do
      resource = described_class.new(name: 'test', password: 'secret')

      expect(resource.property(:enable).insync?(:true)).to be(true)
      expect(resource.property(:enable).insync?(:false)).to be(false)
    end

    it 'rejects invalid user_id' do
      expect do
        described_class.new(name: 'test', enable: :false, user_id: 0)
      end.to raise_error(Puppet::Error, %r{user_id must be an integer between 2 and 63 or "auto"})
    end

    it 'rejects anonymous slot 1 and slots beyond the IPMI range' do
      [1, 64].each do |id|
        expect { described_class.new(name: 'test', enable: :false, user_id: id) }
          .to raise_error(Puppet::Error, %r{between 2 and 63})
      end
    end

    it 'accepts the highest valid slot' do
      expect(described_class.new(name: 'test', enable: :false, user_id: 63)[:user_id]).to eq(63)
    end

    it 'accepts user_id auto as a string' do
      resource = described_class.new(name: 'test', enable: :false, user_id: 'auto')
      expect(resource[:user_id]).to eq(:auto)
    end

    it 'accepts user_id auto as a symbol' do
      resource = described_class.new(name: 'test', enable: :false, user_id: :auto)
      expect(resource[:user_id]).to eq(:auto)
    end

    it 'rejects non-auto string user_id values' do
      expect do
        described_class.new(name: 'test', enable: :false, user_id: 'foo')
      end.to raise_error(Puppet::Error, %r{user_id must be an integer between 2 and 63 or "auto"})
    end
  end

  describe '#generate' do
    let(:strays) { [{ id: 2, name: 'bob' }, { id: 5, name: 'bob' }] }

    # A named provider, usable whether or not ipmitool is installed here, so
    # generate reaches stray_slots instead of deferring the purge.
    before { described_class.provider(:ipmitool).stubs(:suitable?).returns(true) }

    def build(**params)
      described_class.new({ name: 'bob', password: 'secret', channel: 1, user_id: 3, provider: :ipmitool }.merge(params))
    end

    it 'does not purge by default' do
      expect(build.generate).to eq([])
    end

    it 'generates one absent resource per stray slot' do
      resource = build(purge_duplicates: true)
      resource.provider.class.expects(:stray_slots).returns(strays)

      generated = resource.generate

      expect(generated.map { |r| r[:user_id] }).to eq([2, 5])
      expect(generated.map { |r| r[:ensure] }).to all(eq(:absent))
      expect(generated.map { |r| r[:username] }).to all(eq('bob'))
      expect(generated.map(&:title)).to eq(['bob (duplicate in slot 2)', 'bob (duplicate in slot 5)'])
    end

    it 'does not purge for an absent resource' do
      resource = build(purge_duplicates: true, ensure: :absent)
      resource.provider.class.expects(:stray_slots).never

      expect(resource.generate).to eq([])
    end

    it 'passes every ipmi_user in the catalog as peers, since user slots are BMC-wide' do
      resource = build(purge_duplicates: true)
      other = build(name: 'amy', user_id: 4)
      elsewhere = build(name: 'zed', user_id: 5, channel: 2)
      catalog = Puppet::Resource::Catalog.new
      [resource, other, elsewhere].each { |r| catalog.add_resource(r) }
      resource.provider.class.expects(:stray_slots).with(resource, [resource, other, elsewhere]).returns([])

      resource.generate
    end

    it 'runs before the resource that generated it' do
      expect(build).to be_depthfirst
    end
  end

  describe '#pre_run_check' do
    def catalog_with(*param_sets)
      catalog = Puppet::Resource::Catalog.new
      resources = param_sets.map { |params| described_class.new({ password: 'secret', channel: 1 }.merge(params)) }
      resources.each { |r| catalog.add_resource(r) }
      resources
    end

    it 'rejects two live resources with the same username on one channel' do
      first, = catalog_with({ name: 'a', username: 'bob' }, { name: 'b', username: 'bob' })

      expect { first.pre_run_check }.to raise_error(Puppet::Error, %r{manage username bob on channel 1: a, b})
    end

    it 'rejects two live resources claiming the same explicit slot' do
      first, = catalog_with({ name: 'a', user_id: 4 }, { name: 'b', user_id: 4 })

      expect { first.pre_run_check }.to raise_error(Puppet::Error, %r{claim user_id 4})
    end

    it 'allows the same username on different channels' do
      first, = catalog_with({ name: 'a', username: 'bob' }, { name: 'b', username: 'bob', channel: 2 })

      expect { first.pre_run_check }.not_to raise_error
    end

    it 'rejects different usernames claiming one explicit slot on different channels' do
      first, = catalog_with({ name: 'a', user_id: 4 }, { name: 'b', user_id: 4, channel: 2 })

      expect { first.pre_run_check }.to raise_error(Puppet::Error, %r{claim user_id 4 for different usernames: a, b})
    end

    it 'allows several auto resources with different usernames' do
      first, = catalog_with({ name: 'a' }, { name: 'b' })

      expect { first.pre_run_check }.not_to raise_error
    end

    it 'exempts an absent resource for the same username in another explicit slot' do
      first, = catalog_with({ name: 'a', username: 'bob', user_id: 3 }, { name: 'b', username: 'bob', user_id: 4, ensure: :absent })

      expect { first.pre_run_check }.not_to raise_error
    end

    it 'rejects an absent resource that would remove the slot a live one manages' do
      first, = catalog_with({ name: 'a', username: 'bob' }, { name: 'b', username: 'bob', ensure: :absent })

      expect { first.pre_run_check }.to raise_error(Puppet::Error, %r{b \(ensure => absent\) would remove the slot that a manages})
    end
  end

  describe 'when handling sensitive values' do
    it 'marks the password property as sensitive' do
      resource = described_class.new(name: 'test', password: 'secret', enable: :false)

      expect(resource.parameter(:password)).to respond_to(:is_sensitive)
      expect(resource.parameter(:password).is_sensitive).to be(true)
    end

    it 'does not log the plaintext password when applying a change' do
      state_dir = Dir.mktmpdir
      Puppet[:statedir] = state_dir

      resource = described_class.new(
        name: 'test',
        username: 'NEWUSER',
        password: 'supersecret',
        user_id: 4,
        channel: 1,
        enable: :true,
        priv: 4,
        provider: 'ipmitool',
      )
      catalog = Puppet::Resource::Catalog.new
      catalog.add_resource(resource)

      # Prefetch gives the resource a new provider instance, so stub the
      # class: an ipmitool installed on this host must never run.
      Puppet::Util::Execution.expects(:execute).never
      provider_class = resource.provider.class
      provider_class.stubs(:suitable?).returns(true)
      provider_class.stubs(:lan_channels).returns([])
      provider_class.stubs(:read_table).returns([{ id: 4, name: 'NEWUSER', status: :enabled, privs: { 1 => 4 } }])
      provider_class.stubs(:password_matches?).returns(false)
      provider_class.expects(:write_password).with(1, 4, 'supersecret')

      transaction = catalog.apply

      password_logs = transaction.report.logs.select do |log|
        log.source.to_s.include?('/password')
      end
      messages = password_logs.map(&:message).join("\n")

      expect(password_logs).not_to be_empty
      expect(messages).not_to include('supersecret')
      expect(messages).to include('[redacted]')
    ensure
      FileUtils.rm_rf(state_dir)
    end
  end
end
