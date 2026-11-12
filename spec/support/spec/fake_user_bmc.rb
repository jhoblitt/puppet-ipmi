# frozen_string_literal: true

# In-memory BMC used to exercise PuppetX::Ipmi::Provider::UserLogic without a
# real backend.  Every write is applied to the table and recorded in the log.
require 'puppet_x/ipmi/provider/user_logic'

module FakeUserBmc
  # Build a table.  Each entry takes `:id`, `:name`, `:status` (`:enabled`,
  # `:disabled` or `:unknown`), `:priv`, the privilege on every channel, and
  # `:privs`, the privilege on some channels.
  def self.table_with(*entries)
    entries.map { |e| update({ name: '', status: :disabled, privs: {} }, **e) }
  end

  # Change an entry the way table_with builds one.
  #
  # @return [Hash] the entry
  def self.update(entry, priv: nil, privs: {}, **attrs)
    default = priv || entry[:privs].default || PuppetX::Ipmi::Provider::UserLogic::NO_ACCESS_PRIV
    base = priv ? {} : entry[:privs]
    entry.merge!(attrs, privs: Hash.new(default).merge(base).merge(privs))
  end

  # @return [Hash] the entry's name, status and privilege on one channel
  def self.view(entry, channel = 1)
    { name: entry[:name], status: entry[:status], priv: entry[:privs][channel] }
  end

  # Backend primitives; the including class carries its own state.
  module Primitives
    attr_accessor :fake_table, :fake_log, :fake_password, :fake_reads, :fake_lan_channels, :fake_refuses_revoke

    def lan_channels
      fake_lan_channels || []
    end

    def read_table(channels)
      fake_reads&.push(channels)
      fake_table.map do |e|
        raise ArgumentError, "set up slot #{e[:id]} with FakeUserBmc.update: #{e.keys}" unless (e.keys - %i[id name status privs]).empty?

        { id: e[:id], name: e[:name], status: e[:status], privs: channels.to_h { |c| [c, e[:privs][c]] } }
      end
    end

    def check_name(_channel, _id, _name); end

    def check_password(_channel, _id, _password); end

    def write_name(_channel, id, name)
      fake_log << [:name, id, name]
      slot(id)[:name] = name
    end

    def write_password(_channel, id, password)
      fake_log << [:password, id, password]
    end

    def password_matches?(_channel, _id, password)
      password == fake_password
    end

    def write_priv(channel, id, priv)
      fake_log << [:priv, id, priv]
      slot(id)[:privs][channel] = priv
    end

    # A BMC that does not report whether an account is enabled keeps
    # reporting `:unknown`.
    def grant_access(channel, id, priv)
      fake_log << [:grant, id, priv]
      entry = slot(id)
      entry[:privs][channel] = priv
      entry[:status] = :enabled unless entry[:status] == :unknown
    end

    # With fake_refuses_revoke set, the BMC refuses every permission change,
    # as some do on an account that is not enabled; the refusals reach
    # disable_failing_closed the way a backend's do.
    def revoke_access(channels, id, already_disabled: false)
      fake_log << [:revoke, id, channels]
      entry = slot(id)
      revokes = channels.map do |channel|
        lambda do
          raise Puppet::ExecutionFailure, 'refused' if fake_refuses_revoke

          entry[:privs][channel] = PuppetX::Ipmi::Provider::UserLogic::NO_ACCESS_PRIV
        end
      end
      disable = ->(_on) { entry[:status] = :disabled unless entry[:status] == :unknown }
      disable_failing_closed(id, revokes: revokes, set_enabled: disable, already_disabled: already_disabled)
    end

    def slot(id)
      fake_table.find { |u| u[:id] == id }
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
  # @param name [Symbol] the provider's name
  # @return [Class]
  def self.registered_provider(name = :fake_bmc)
    type = Puppet::Type.type(:ipmi_user)
    existing = type.provider(name)
    return existing if existing

    type.provide(name, parent: PuppetX::Ipmi::Provider::Base) do
      desc 'Test-only in-memory BMC'
      confine true: false
      include PuppetX::Ipmi::Provider::UserLogic
      include FakeUserBmc::Instance
      extend FakeUserBmc::Primitives
    end
  end
end
