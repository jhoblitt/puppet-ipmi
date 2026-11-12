# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_user'
require 'puppet_x/ipmi/user_catalog'

describe PuppetX::Ipmi::UserCatalog do
  let(:type) { Puppet::Type.type(:ipmi_user) }

  # A named provider, so the provider does not depend on which IPMI tools
  # are installed here or on the default an earlier spec left cached.
  def build(**params)
    type.new({ name: 'bob', password: 'secret', channel: 1, user_id: 3, provider: :ipmitool }.merge(params).compact)
  end

  def catalog_with(*resources)
    catalog = Puppet::Resource::Catalog.new
    resources.each { |r| catalog.add_resource(r) }
    catalog
  end

  describe '.bmc_peers' do
    it 'returns only the resource when it has no catalog' do
      resource = build

      expect(described_class.bmc_peers(resource)).to eq([resource])
    end

    it 'returns every ipmi_user on every channel' do
      resource = build
      other = build(name: 'amy', user_id: 4)
      elsewhere = build(name: 'zed', user_id: 5, channel: 2)
      catalog_with(resource, other, elsewhere)

      expect(described_class.bmc_peers(resource)).to contain_exactly(resource, other, elsewhere)
    end
  end

  describe '.duplicate_resources' do
    it 'returns nothing unless purge_duplicates is set' do
      expect(described_class.duplicate_resources(build)).to eq([])
    end

    it 'returns nothing for an absent resource' do
      resource = build(purge_duplicates: true, ensure: :absent)
      resource.provider.class.expects(:stray_slots).never

      expect(described_class.duplicate_resources(resource)).to eq([])
    end

    it 'builds an absent resource per stray slot carrying the username and channel' do
      resource = build(purge_duplicates: true)
      resource.provider.class.stubs(:suitable?).returns(true)
      resource.provider.class.expects(:stray_slots).returns([{ id: 2, name: 'bob' }])

      generated = described_class.duplicate_resources(resource)

      expect(generated.map(&:title)).to eq(['bob (duplicate in slot 2)'])
      expect(generated.first.to_hash).to include(ensure: :absent, username: 'bob', user_id: 2, channel: 1)
    end

    it 'defers the purge with a notice when the resource has no provider' do
      resource = build(purge_duplicates: true)
      resource.stubs(:provider).returns(nil)
      resource.expects(:notice).with(regexp_matches(%r{purge_duplicates is deferred}))

      expect(described_class.duplicate_resources(resource)).to eq([])
    end

    it 'defers the purge with a notice while the provider is not usable yet' do
      resource = build(purge_duplicates: true)
      resource.provider.class.stubs(:suitable?).returns(false)
      resource.provider.class.expects(:stray_slots).never
      resource.expects(:notice).with(regexp_matches(%r{purge_duplicates is deferred}))

      expect(described_class.duplicate_resources(resource)).to eq([])
    end

    it 'skips the purge with a warning when the BMC user table cannot be read' do
      resource = build(purge_duplicates: true)
      resource.provider.class.stubs(:suitable?).returns(true)
      resource.provider.class.expects(:stray_slots).raises(Puppet::ExecutionFailure, 'Unable to establish IPMI v2 / RMCP+ session')
      resource.expects(:warning).with(regexp_matches(%r{purge_duplicates is skipped.*Unable to establish}))

      expect(described_class.duplicate_resources(resource)).to eq([])
    end
  end

  describe '.check_unique!' do
    it 'is a no-op without a catalog' do
      expect { described_class.check_unique!(build) }.not_to raise_error
    end

    it 'is a no-op for an absent resource' do
      a = build(name: 'a', username: 'bob', ensure: :absent)
      catalog_with(a, build(name: 'b', username: 'bob', user_id: 4))

      expect { described_class.check_unique!(a) }.not_to raise_error
    end

    it 'rejects a duplicate username, naming every claimant sorted' do
      a = build(name: 'b', username: 'bob', user_id: 3)
      catalog_with(a, build(name: 'a', username: 'bob', user_id: 4))

      expect { described_class.check_unique!(a) }
        .to raise_error(Puppet::Error, %r{manage username bob on channel 1: a, b})
    end

    it 'rejects a duplicate explicit slot' do
      a = build(name: 'a', user_id: 4)
      catalog_with(a, build(name: 'b', user_id: 4))

      expect { described_class.check_unique!(a) }
        .to raise_error(Puppet::Error, %r{claim user_id 4 for different usernames: a, b})
    end

    it 'allows several auto resources' do
      a = build(name: 'a', user_id: :auto)
      catalog_with(a, build(name: 'b', user_id: :auto))

      expect { described_class.check_unique!(a) }.not_to raise_error
    end

    it 'rejects an absent auto resource for the username of a present one' do
      a = build(name: 'alice', user_id: :auto)
      catalog_with(a, build(name: 'alice-gone', username: 'alice', user_id: :auto, ensure: :absent))

      expect { described_class.check_unique!(a) }
        .to raise_error(Puppet::Error, %r{alice-gone \(ensure => absent\) would remove the slot that alice manages for username alice})
    end

    it 'rejects an absent resource for the same username and explicit slot' do
      a = build(name: 'alice', user_id: 3)
      catalog_with(a, build(name: 'alice-gone', username: 'alice', user_id: 3, ensure: :absent))

      expect { described_class.check_unique!(a) }.to raise_error(Puppet::Error, %r{alice-gone \(ensure => absent\)})
    end

    it 'rejects an absent auto resource for the username of an explicit one' do
      a = build(name: 'alice', user_id: 3)
      catalog_with(a, build(name: 'alice-gone', username: 'alice', user_id: :auto, ensure: :absent))

      expect { described_class.check_unique!(a) }.to raise_error(Puppet::Error, %r{alice-gone \(ensure => absent\)})
    end

    it 'allows an absent resource for the same username in another explicit slot' do
      a = build(name: 'alice', user_id: 3)
      catalog_with(a, build(name: 'alice (duplicate in slot 4)', username: 'alice', user_id: 4, ensure: :absent))

      expect { described_class.check_unique!(a) }.not_to raise_error
    end

    it 'allows an absent resource for another username' do
      a = build(name: 'alice', user_id: :auto)
      catalog_with(a, build(name: 'old', user_id: :auto, ensure: :absent))

      expect { described_class.check_unique!(a) }.not_to raise_error
    end

    # User slots and names are BMC-wide; only access is per channel.
    describe 'across channels' do
      it 'rejects different usernames claiming one explicit slot' do
        a = build(name: 'a', user_id: 4)
        catalog_with(a, build(name: 'b', user_id: 4, channel: 2))

        expect { described_class.check_unique!(a) }
          .to raise_error(Puppet::Error, %r{claim user_id 4 for different usernames: a, b})
      end

      it 'rejects one username in different explicit slots' do
        a = build(name: 'a', username: 'bob', user_id: 3)
        catalog_with(a, build(name: 'b', username: 'bob', user_id: 4, channel: 2))

        expect { described_class.check_unique!(a) }
          .to raise_error(Puppet::Error, %r{username bob in different user_id slots: a, b})
      end

      it 'allows one username with an explicit slot on one channel and auto on another' do
        a = build(name: 'a', username: 'bob', user_id: 4)
        b = build(name: 'b', username: 'bob', user_id: :auto, channel: 2)
        catalog_with(a, b)

        expect { described_class.check_unique!(a) }.not_to raise_error
        expect { described_class.check_unique!(b) }.not_to raise_error
      end

      it 'allows one username in one explicit slot on several channels' do
        a = build(name: 'a', username: 'bob', user_id: 4)
        catalog_with(a, build(name: 'b', username: 'bob', user_id: 4, channel: 2))

        expect { described_class.check_unique!(a) }.not_to raise_error
      end

      it 'allows one auto username on several channels' do
        a = build(name: 'a', username: 'bob', user_id: :auto)
        catalog_with(a, build(name: 'b', username: 'bob', user_id: :auto, channel: 2))

        expect { described_class.check_unique!(a) }.not_to raise_error
      end

      it 'rejects an absent auto resource for the username of a present one' do
        a = build(name: 'alice', user_id: :auto)
        catalog_with(a, build(name: 'alice-gone', username: 'alice', user_id: :auto, channel: 2, ensure: :absent))

        expect { described_class.check_unique!(a) }
          .to raise_error(Puppet::Error, %r{alice-gone \(ensure => absent\) would remove the slot that alice manages for username alice})
      end

      it 'rejects an absent resource naming the explicit slot of a present one with its username' do
        a = build(name: 'alice', user_id: 3)
        catalog_with(a, build(name: 'alice-gone', username: 'alice', user_id: 3, channel: 2, ensure: :absent))

        expect { described_class.check_unique!(a) }.to raise_error(Puppet::Error, %r{alice-gone \(ensure => absent\)})
      end

      it 'allows an absent resource for the username in another explicit slot' do
        a = build(name: 'alice', user_id: 3)
        catalog_with(a, build(name: 'alice (duplicate in slot 4)', username: 'alice', user_id: 4, channel: 2, ensure: :absent))

        expect { described_class.check_unique!(a) }.not_to raise_error
      end

      # One username is one account, so its enabled state and password are
      # the same on every channel.
      it 'rejects one username whose resources disagree on enable' do
        a = build(name: 'a', username: 'bob')
        catalog_with(a, build(name: 'b', username: 'bob', channel: 2, enable: :false, password: nil))

        expect { described_class.check_unique!(a) }
          .to raise_error(Puppet::Error, %r{a, b manage username bob but disagree on enable})
      end

      it 'rejects one username whose resources declare different passwords, without echoing them' do
        a = build(name: 'a', username: 'bob', password: 'first-secret')
        catalog_with(a, build(name: 'b', username: 'bob', channel: 2, password: Puppet::Pops::Types::PSensitiveType::Sensitive.new('other-secret')))

        expect { described_class.check_unique!(a) }.to raise_error(Puppet::Error, %r{a, b manage username bob but disagree on password}) do |e|
          expect(e.message).not_to match(%r{first-secret|other-secret})
        end
      end

      it 'allows one username with different privileges, and the same password wrapped or not' do
        a = build(name: 'a', username: 'bob', priv: 4)
        catalog_with(a, build(name: 'b', username: 'bob', channel: 2, priv: 2, password: Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret')))

        expect { described_class.check_unique!(a) }.not_to raise_error
      end

      it 'allows a password only one of the resources declares' do
        a = build(name: 'a', username: 'bob', enable: :false)
        catalog_with(a, build(name: 'b', username: 'bob', channel: 2, enable: :false, password: nil))

        expect { described_class.check_unique!(a) }.not_to raise_error
      end
    end
  end
end
