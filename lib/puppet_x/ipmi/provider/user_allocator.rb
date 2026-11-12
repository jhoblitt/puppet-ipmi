# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/base'

# Assigns BMC user slots to `ipmi_user` resources.
#
# Design rationale: allocation is a pure function of the BMC's user table and
# the set of resources in the catalog.  It holds no state between calls and does
# not depend on the order in which Puppet evaluates resources, so two runs
# against the same BMC and catalog always give the same answer.  That keeps
# slot assignment reproducible across a fleet.
#
# User slots and names are BMC-wide; only access is per channel.  So the
# resources of every channel are allocated together, and `auto` resources
# that share a username (the same user on several channels) share a slot.
#
# Rules, in order:
#
# 1. Explicit `user_id` values are reserved first and always win.
# 2. An `auto` username that an explicit resource names takes that slot.
# 3. An `auto` username that already holds a slot keeps it: the lowest id
#    holding the username that no explicit resource reserved, and that no
#    absent resource for the username names explicitly, since that one is
#    to be retired.
# 4. The remaining `auto` usernames, sorted by their first title, take the
#    lowest free slots.  A slot is free when its id is 2 or more (slot 1 is
#    the anonymous user), its name is empty or `DISABLED_*`, it is not
#    reported enabled, and no channel in the table grants it a privilege.
# 5. Resources with `ensure => absent` never reserve or consume a slot; they
#    only report the slot they currently occupy, if any, and get an error
#    when a present resource was given that slot.
module PuppetX::Ipmi::Provider::UserAllocator
  # @param table [Array<Hash>] BMC user table (see UserLogic)
  # @param requests [Array<Hash>] one per resource, with `:title`,
  #   `:username`, `:user_id` (Integer or :auto) and `:present` (Boolean)
  # @return [Hash<String, Hash>] title => `{ id: Integer, nil }` or
  #   `{ error: String }`
  def self.allocate(table, requests)
    logic = PuppetX::Ipmi::Provider::UserLogic
    results = {}
    present, absent = requests.partition { |r| r[:present] }
    explicit, auto = present.partition { |r| r[:user_id] != :auto }

    reserved = explicit.map { |r| r[:user_id] }
    explicit.each { |r| results[r[:title]] = { id: r[:user_id] } }

    absent.each do |r|
      slot = logic.existing_slot(table, r[:username], r[:user_id])
      results[r[:title]] = { id: slot&.fetch(:id) }
    end

    pending = []
    auto.group_by { |r| r[:username] }.sort_by { |_, group| group.map { |r| r[:title] }.min }.each do |username, group|
      retired = absent.select { |r| r[:username] == username && r[:user_id] != :auto }.map { |r| r[:user_id] }
      id = explicit.select { |r| r[:username] == username }.map { |r| r[:user_id] }.min
      id ||= logic.existing_slot(table, username, :auto, skip: reserved + retired)&.fetch(:id)
      if id
        group.each { |r| results[r[:title]] = { id: id } }
        reserved << id
      else
        pending << [username, group]
      end
    end

    free = table.select { |u| logic.free_slot?(u) }.map { |u| u[:id] }.sort - reserved
    pending.each do |username, group|
      id = free.shift
      group.each do |r|
        results[r[:title]] = if id.nil?
                               { error: "No free IPMI user slot available for #{username}" }
                             else
                               { id: id }
                             end
      end
    end

    refuse_absent_on_present_slots(results, present, absent)
  end

  # An absent resource must not remove a slot a present resource was given,
  # or the two undo each other on every run.  The pre-run check catches
  # what the catalog alone shows; this catches what depends on the table,
  # such as the slot an explicit id takes over from the absent resource's
  # username.  The absent resource keeps its id, so it still reads as
  # present and fails when Puppet tries to remove it.
  #
  # @return [Hash<String, Hash>] the results
  def self.refuse_absent_on_present_slots(results, present, absent)
    owners = present.group_by { |r| results[r[:title]][:id] }.transform_values { |group| group.map { |r| r[:title] }.min }
    absent.each do |r|
      id = results[r[:title]][:id]
      owner = owners[id] if id
      next unless owner

      results[r[:title]] = { id: id, error: "#{r[:title]} (ensure => absent) would remove slot #{id}, which #{owner} manages" }
    end
    results
  end
  private_class_method :refuse_absent_on_present_slots
end
