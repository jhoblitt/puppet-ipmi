# frozen_string_literal: true

require 'puppet'
require 'puppet/provider'
require 'set'
require 'shellwords'

# Base provider for IPMI-managed resources.
#
# Provides generic helpers shared across all IPMI tool implementations.
# Tool-specific execution (ipmitool, bmc-config) lives in the concrete
# provider files rather than here.
class Puppet::Provider::Ipmi < Puppet::Provider
  # IDs already reserved by `user_id => 'auto'` during this Puppet run.
  # This prevents multiple auto resources from selecting the same slot
  # before earlier resources have actually written to the BMC.
  AUTO_ALLOCATED_USER_IDS = Set.new

  def self.reset_auto_allocated_user_ids!
    AUTO_ALLOCATED_USER_IDS.clear
  end

  # Shell-escape a value for safe interpolation into command strings.
  def shellescape(val)
    Shellwords.escape(val.to_s)
  end

  # Parse colon-separated key-value output (lines like "Key  : Value").
  # Used by any provider that reads structured output in this format.
  def parse_colon_kv(output)
    result = {}
    return result if output.nil? || output.empty?

    output.each_line do |line|
      next unless line.include?(':')

      parts = line.split(':', 2)
      key = parts[0].strip
      value = parts[1].strip
      result[key] = value unless key.empty?
    end
    result
  end

  # Resolve `user_id => 'auto'` to a concrete BMC user slot.
  #
  # `users` is an array of hashes of the form `{ id: Integer, name: String }`
  # describing the current BMC user slots.  A name that is empty or starts
  # with `DISABLED_` is treated as a free slot.
  #
  # Returns the ID of an existing user whose name matches `user_name`, or the
  # lowest unused ID reported by the BMC.  ID 1 is never returned.  If no
  # free slot is available, a Puppet::Error is raised.
  #
  # IDs selected during the current Puppet run are recorded in
  # AUTO_ALLOCATED_USER_IDS so that multiple `auto` resources cannot
  # resolve to the same slot before any of them have been applied.
  def resolve_auto_user_id(user_name, users)
    existing = users.find { |u| u[:name] == user_name }
    if existing
      AUTO_ALLOCATED_USER_IDS << existing[:id]
      return existing[:id]
    end

    max_id = users.map { |u| u[:id] }.max || 15
    used_ids = users.filter_map do |u|
      name = u[:name].to_s
      u[:id] unless name.empty? || name =~ %r{^DISABLED_}
    end

    used_ids.concat(AUTO_ALLOCATED_USER_IDS.to_a)

    (2..max_id).each do |id|
      next if used_ids.include?(id)

      AUTO_ALLOCATED_USER_IDS << id
      return id
    end

    raise Puppet::Error, "No free IPMI user slot available for #{user_name}"
  end
end
