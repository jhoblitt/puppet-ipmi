# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_user'
require 'puppet_x/ipmi/user_catalog'

describe PuppetX::Ipmi::UserCatalog do
  let(:type) { Puppet::Type.type(:ipmi_user) }

  def build(**params)
    type.new({ name: 'bob', password: 'secret', channel: 1, user_id: 3 }.merge(params))
  end

  def catalog_with(*resources)
    catalog = Puppet::Resource::Catalog.new
    resources.each { |r| catalog.add_resource(r) }
    catalog
  end

  describe '.channel_peers' do
    it 'returns only the resource when it has no catalog' do
      resource = build

      expect(described_class.channel_peers(resource)).to eq([resource])
    end

    it 'returns every ipmi_user on the same channel' do
      resource = build
      other = build(name: 'amy', user_id: 4)
      elsewhere = build(name: 'zed', user_id: 4, channel: 2)
      catalog_with(resource, other, elsewhere)

      expect(described_class.channel_peers(resource)).to contain_exactly(resource, other)
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
      resource.provider.class.expects(:stray_slots).returns([{ id: 2, name: 'bob' }])

      generated = described_class.duplicate_resources(resource)

      expect(generated.map(&:title)).to eq(['bob (duplicate in slot 2)'])
      expect(generated.first.to_hash).to include(ensure: :absent, username: 'bob', user_id: 2, channel: 1)
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

      expect { described_class.check_unique!(a) }.
        to raise_error(Puppet::Error, %r{manage username bob on channel 1: a, b})
    end

    it 'rejects a duplicate explicit slot' do
      a = build(name: 'a', user_id: 4)
      catalog_with(a, build(name: 'b', user_id: 4))

      expect { described_class.check_unique!(a) }.
        to raise_error(Puppet::Error, %r{claim user_id 4 on channel 1: a, b})
    end

    it 'allows several auto resources' do
      a = build(name: 'a', user_id: :auto)
      catalog_with(a, build(name: 'b', user_id: :auto))

      expect { described_class.check_unique!(a) }.not_to raise_error
    end

    it 'allows the same slot on different channels' do
      a = build(name: 'a', user_id: 4)
      catalog_with(a, build(name: 'b', user_id: 4, channel: 2))

      expect { described_class.check_unique!(a) }.not_to raise_error
    end
  end
end
