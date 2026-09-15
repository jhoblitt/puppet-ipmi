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
# Rules, in order:
#
# 1. Explicit `user_id` values are reserved first and always win.
# 2. An `auto` resource whose username already holds a slot keeps that slot
#    (lowest id if several), unless an explicit resource reserved it.
# 3. The remaining `auto` resources, sorted by title, take the lowest free
#    slots.  A slot is free when its id is 2 or more (slot 1 is the anonymous
#    user) and its name is empty or `DISABLED_*`.
# 4. Resources with `ensure => absent` never reserve or consume a slot; they
#    only report the slot they currently occupy, if any.
module PuppetX::Ipmi::Provider::UserAllocator
  # @param table [Array<Hash>] BMC user table (`:id`, `:name`)
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
    auto.sort_by { |r| r[:title] }.each do |r|
      slot = logic.existing_slot(table, r[:username], :auto)
      if slot && !reserved.include?(slot[:id])
        results[r[:title]] = { id: slot[:id] }
        reserved << slot[:id]
      else
        pending << r
      end
    end

    free = table.select { |u| u[:id] >= 2 && logic.free_name?(u[:name]) }.map { |u| u[:id] }.sort - reserved
    pending.each do |r|
      id = free.shift
      results[r[:title]] = if id.nil?
                             { error: "No free IPMI user slot available for #{r[:username]}" }
                           else
                             { id: id }
                           end
    end

    results
  end
end
