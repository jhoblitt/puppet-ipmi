# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_user'

describe Puppet::Type.type(:ipmi_user).provider(:ipmitool) do
  let(:type) { Puppet::Type.type(:ipmi_user) }
  let(:base_params) do
    {
      name: 'test',
      user: 'NEWUSER',
      password: 'secret',
      channel: 1,
      provider: 'ipmitool',
    }
  end
  let(:asus_list) do
    File.read('spec/fixtures/unit/puppet/provider/ipmi_user/ipmitool_user_list_asus.txt')
  end
  let(:supermicro_list) do
    File.read('spec/fixtures/unit/puppet/provider/ipmi_user/ipmitool_user_list_supermicro.txt')
  end

  before do
    Puppet::Provider::Ipmi.reset_auto_allocated_user_ids!
  end

  def resource_for(user_id)
    type.new(base_params.merge(user_id: user_id))
  end

  describe 'with explicit user_id' do
    let(:provider) { resource_for(4).provider }

    it 'returns the requested id' do
      expect(provider.resolved_user_id).to eq(4)
    end
  end

  describe 'with user_id => auto' do
    let(:provider) { resource_for('auto').provider }

    it 'reuses the id of an existing user with the same name' do
      slam_resource = type.new(base_params.merge(user: 'SLAM', user_id: 'auto'))
      slam_provider = slam_resource.provider

      slam_provider.expects(:ipmitool_exec).with('user list 1 2>/dev/null').returns(asus_list)

      expect(slam_provider.resolved_user_id).to eq(4)
    end

    it 'selects the lowest free slot, skipping id 1' do
      provider.expects(:ipmitool_exec).with('user list 1 2>/dev/null').returns(supermicro_list)

      expect(provider.resolved_user_id).to eq(3)
    end

    it 'treats DISABLED_* slots as free' do
      disabled_list = asus_list.gsub('Administrator', 'DISABLED_5')

      provider.expects(:ipmitool_exec).with('user list 1 2>/dev/null').returns(disabled_list)

      expect(provider.resolved_user_id).to eq(5)
    end

    it 'falls back to a maximum of 15 when the user list is empty' do
      provider.expects(:ipmitool_exec).with('user list 1 2>/dev/null').returns('')

      expect(provider.resolved_user_id).to eq(2)
    end

    it 'raises when no free slot is available' do
      full_list = "ID  Name             Callin  Link Auth  IPMI Msg   Channel Priv Limit\n"
      (2..15).each do |id|
        full_list += "#{id}   user#{id}            true    true       true       ADMINISTRATOR\n"
      end

      provider.expects(:ipmitool_exec).with('user list 1 2>/dev/null').returns(full_list)

      expect { provider.resolved_user_id }.to raise_error(Puppet::Error, %r{No free IPMI user slot})
    end

    it 'allocates distinct ids for multiple auto resources' do
      resource_a = type.new(base_params.merge(name: 'a', user: 'A', user_id: 'auto'))
      resource_b = type.new(base_params.merge(name: 'b', user: 'B', user_id: 'auto'))
      provider_a = resource_a.provider
      provider_b = resource_b.provider

      provider_a.expects(:ipmitool_exec).with('user list 1 2>/dev/null').returns(supermicro_list)
      provider_b.expects(:ipmitool_exec).with('user list 1 2>/dev/null').returns(supermicro_list)

      id_a = provider_a.resolved_user_id
      id_b = provider_b.resolved_user_id

      expect(id_a).not_to eq(id_b)
      expect([id_a, id_b]).to all(be >= 2)
    end
  end
end
