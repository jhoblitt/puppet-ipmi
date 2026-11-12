# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/ipmi/provider/user_allocator'

describe PuppetX::Ipmi::Provider::UserAllocator do
  let(:table) do
    FakeUserBmc.table_with(
      { id: 1 },
      { id: 2, name: 'ADMIN', priv: 4, enabled: true },
      { id: 3 },
      { id: 4, name: 'DISABLED_4' },
      { id: 5 },
    )
  end

  def request(title, user_id: :auto, present: true, username: title)
    { title: title, username: username, user_id: user_id, present: present }
  end

  def ids(results)
    results.transform_values { |r| r[:id] }
  end

  it 'gives auto resources the lowest free slots in title order' do
    results = described_class.allocate(table, [request('zed'), request('amy'), request('bob')])

    expect(ids(results)).to eq('amy' => 3, 'bob' => 4, 'zed' => 5)
  end

  it 'is independent of the order resources are supplied in' do
    requests = [request('c'), request('a'), request('b')]

    expect(described_class.allocate(table, requests)).to eq(described_class.allocate(table, requests.reverse))
  end

  it 'never uses the anonymous slot and treats DISABLED_* as free' do
    table[2][:name] = 'taken'
    expect(ids(described_class.allocate(table, [request('amy')]))).to eq('amy' => 4)
  end

  it 'keeps an existing slot stable' do
    table[4][:name] = 'bob'
    results = described_class.allocate(table, [request('amy'), request('bob')])

    expect(ids(results)).to eq('amy' => 3, 'bob' => 5)
  end

  it 'reserves explicit ids before allocating auto resources' do
    results = described_class.allocate(table, [request('amy'), request('fixed', user_id: 3)])

    expect(ids(results)).to eq('amy' => 4, 'fixed' => 3)
  end

  it 'lets an explicit id win over an existing auto match' do
    table[2][:name] = 'bob'
    results = described_class.allocate(table, [request('bob'), request('fixed', user_id: 3)])

    expect(ids(results)).to eq('bob' => 4, 'fixed' => 3)
  end

  it 'reports an error only for the resources that find no slot' do
    results = described_class.allocate(table, %w[a b c d].map { |n| request(n) })

    expect(ids(results).compact).to eq('a' => 3, 'b' => 4, 'c' => 5)
    expect(results['d'][:error]).to match(%r{No free IPMI user slot available for d})
  end

  it 'lets absent resources report their slot without consuming one' do
    table[0][:name] = 'old'
    table[2][:name] = 'old'
    results = described_class.allocate(table, [request('old', present: false), request('amy')])

    expect(ids(results)).to eq('old' => 3, 'amy' => 4)
  end

  it 'gives an absent resource with no slot a nil id and no error' do
    expect(described_class.allocate(table, [request('ghost', present: false)])).to eq('ghost' => { id: nil })
  end

  it 'never allocates the anonymous slot even when it is empty' do
    table[0].merge!(name: '')
    expect(ids(described_class.allocate(table, [request('amy')]))).to eq('amy' => 3)
  end

  it 'honors an explicit id even when that slot is already occupied' do
    # The allocator is a pure slot-numbering function; it hands the slot and
    # does not rename its occupant.  The type's pre_run_check is responsible
    # for catching a name that two resources disagree about.
    results = described_class.allocate(table, [request('amy'), request('fixed', user_id: 2)])

    expect(ids(results)).to eq('amy' => 3, 'fixed' => 2)
  end
end
