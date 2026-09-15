# frozen_string_literal: true

# In-memory BMC used to exercise PuppetX::Ipmi::Provider::UserLogic without a
# real backend.  Every write is applied to the table and recorded in the log.
require 'puppet_x/ipmi/provider/user_logic'

module FakeUserBmc
  def self.table_with(*entries)
    entries.map { |e| { name: '', priv: PuppetX::Ipmi::Provider::UserLogic::NO_ACCESS_PRIV, enabled: false }.merge(e) }
  end

  # Backend primitives; the including class carries its own state.
  module Primitives
    attr_accessor :fake_table, :fake_log, :fake_password

    def read_users(_channel)
      fake_table.map(&:dup)
    end

    def write_name(_channel, id, name)
      fake_log << [:name, id, name]
      fake_table.find { |u| u[:id] == id }[:name] = name
    end

    def write_password(_channel, id, password)
      fake_log << [:password, id, password]
    end

    def password_matches?(_channel, _id, password)
      password == fake_password
    end

    def write_priv(_channel, id, priv)
      fake_log << [:priv, id, priv]
      fake_table.find { |u| u[:id] == id }[:priv] = priv
    end

    def write_access(_channel, id, enabled, priv)
      fake_log << [:access, id, enabled, priv]
      entry = fake_table.find { |u| u[:id] == id }
      entry[:enabled] = enabled
      entry[:priv] = priv
    end
  end

  module Instance
    def channel
      @resource[:channel]
    end
  end

  # @return [Class] an unregistered provider class bound to the given state
  def self.provider_class(table, log, password: nil)
    Class.new(PuppetX::Ipmi::Provider::Base) do
      include PuppetX::Ipmi::Provider::UserLogic
      include FakeUserBmc::Instance
      extend FakeUserBmc::Primitives

      self.fake_table = table
      self.fake_log = log
      self.fake_password = password
    end
  end

  # Register (once) an `ipmi_user` provider that is never chosen by default
  # and return it, for specs that need to run a real catalog.
  #
  # @return [Class]
  def self.registered_provider
    type = Puppet::Type.type(:ipmi_user)
    existing = type.provider(:fake_bmc)
    return existing if existing

    type.provide(:fake_bmc, parent: PuppetX::Ipmi::Provider::Base) do
      desc 'Test-only in-memory BMC'
      confine true: false
      include PuppetX::Ipmi::Provider::UserLogic
      include FakeUserBmc::Instance
      extend FakeUserBmc::Primitives
    end
  end
end
