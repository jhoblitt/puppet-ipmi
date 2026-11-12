# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/ipmi/provider/base'

describe PuppetX::Ipmi::Provider::Base do
  describe '.parse_colon_kv' do
    it 'parses "Key : Value" lines and strips whitespace' do
      expect(described_class.parse_colon_kv("IP Address   : 10.0.0.1\nSubnet Mask  : 255.0.0.0\n"))
        .to eq('IP Address' => '10.0.0.1', 'Subnet Mask' => '255.0.0.0')
    end

    it 'splits only on the first colon' do
      expect(described_class.parse_colon_kv("MAC Address : 00:11:22:33:44:55\n"))
        .to eq('MAC Address' => '00:11:22:33:44:55')
    end

    it 'skips lines without a colon and empty keys' do
      expect(described_class.parse_colon_kv("no separator\n : orphan\nKey : v\n")).to eq('Key' => 'v')
    end

    it 'keeps an empty value' do
      expect(described_class.parse_colon_kv("Key :\n")).to eq('Key' => '')
    end

    it 'returns an empty hash for nil or empty output' do
      expect([described_class.parse_colon_kv(nil), described_class.parse_colon_kv('')]).to eq([{}, {}])
    end

    it 'delegates from the instance method' do
      expect(described_class.allocate.parse_colon_kv("A : b\n")).to eq('A' => 'b')
    end
  end

  describe '.with_secret_file' do
    it 'yields a mode 0600 file holding the content' do
      described_class.with_secret_file('secret') do |path|
        expect(File.stat(path).mode & 0o777).to eq(0o600)
        expect(File.read(path)).to eq('secret')
      end
    end

    it 'returns the block result and removes the file' do
      path = nil
      result = described_class.with_secret_file('secret') do |p|
        path = p
        :done
      end

      expect(result).to eq(:done)
      expect(File.exist?(path)).to be(false)
    end

    it 'removes the file when the block raises' do
      path = nil
      expect do
        described_class.with_secret_file('secret') do |p|
          path = p
          raise Puppet::Error, 'boom'
        end
      end.to raise_error(Puppet::Error, 'boom')

      expect(File.exist?(path)).to be(false)
    end
  end

  describe 'channel helpers' do
    let(:provider) { described_class.allocate }

    it 'reads channel and lan_channel from the resource' do
      provider.instance_variable_set(:@resource, { channel: 2, lan_channel: 3 })

      expect([provider.channel, provider.lan_channel]).to eq([2, 3])
    end
  end
end
