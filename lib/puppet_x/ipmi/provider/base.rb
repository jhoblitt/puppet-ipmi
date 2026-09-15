# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi'
require 'puppet/provider'
require 'tempfile'

# Base provider for IPMI-managed resources.
#
# Provides generic helpers shared across all IPMI tool implementations.
# Tool-specific execution helpers live in PuppetX::Ipmi::Provider::Ipmitool
# and PuppetX::Ipmi::Provider::Freeipmi.
class PuppetX::Ipmi::Provider::Base < Puppet::Provider
  # The lengths a tool or BMC cuts a secret to: 16 or 20 bytes for a
  # password, 18 for a community.
  SECRET_CUTS = [16, 18, 20].freeze

  # Run a backend command.
  #
  # Puppet puts a failed command's output in the error it raises, even for
  # a sensitive command, so one whose output may hold a secret runs without
  # failonfail and fails here instead, with its output scrubbed.
  #
  # @param cmd [Array<String>] the command and its arguments
  # @param echoes [Hash{Regexp => String}] output lines that carry a secret,
  #   and what replaces each
  # @param failonfail [Boolean] whether to raise on non-zero exit
  # @param sensitive [Boolean] whether to redact the command in logs and
  #   scrub the output of a failure
  # @param scrub [Boolean] scrub the output of a failure without redacting
  #   the command, for a read whose output holds a secret
  # @param redact [Array<String>] values to keep out of a failure's output
  # @param stdinfile [String, nil] path of a file to feed on stdin
  # @return [Puppet::Util::Execution::ProcessOutput]
  def self.execute_scrubbed(cmd, echoes:, failonfail:, sensitive:, scrub:, redact:, stdinfile: nil)
    scrubbed = sensitive || scrub
    options = { failonfail: failonfail && !scrubbed, combine: true }
    options[:sensitive] = true if sensitive
    options[:stdinfile] = stdinfile if stdinfile
    output = Puppet::Util::Execution.execute(cmd, options)
    return output unless scrubbed && failonfail && !output.exitstatus.zero?

    shown = cmd.join(' ')
    shown = '[redacted]' if sensitive
    raise Puppet::ExecutionFailure, "Execution of '#{shown}' returned #{output.exitstatus}: #{scrub_output(output.strip, redact, echoes)}"
  end

  # Replace each of `echoes`' lines, then each value and the lengths it may
  # be cut to (SECRET_CUTS), longest first.
  #
  # @param output [String]
  # @param values [Array<String>]
  # @param echoes [Hash{Regexp => String}]
  # @return [String] output without the echoed lines or any form of values
  def self.scrub_output(output, values, echoes)
    text = echoes.reduce(output.b) { |acc, (line, placeholder)| acc.gsub(line, placeholder) }
    forms = values.map { |v| v.to_s.b }.reject(&:empty?).flat_map { |v| [v] + SECRET_CUTS.map { |n| v.byteslice(0, n) } }
    text = forms.uniq.sort_by { |f| -f.bytesize }.reduce(text) { |acc, elem| acc.gsub(elem, '[redacted]') }
    text.force_encoding(Encoding::UTF_8).scrub
  end

  # Hand a secret to a command through a file instead of its argv, which
  # any local user can read from ps or /proc/<pid>/cmdline.  The file is
  # created in Dir.tmpdir with O_EXCL and mode 0600, and is removed when the
  # block returns or raises.
  #
  # @param content [String] the file's content
  # @yieldparam path [String] the file's path
  # @return the block's result
  def self.with_secret_file(content)
    Tempfile.create('puppet-ipmi') do |file|
      file.write(content)
      file.close
      yield file.path
    end
  end

  # Parse colon-separated key-value output (lines like "Key  : Value").
  # Used by any provider that reads structured output in this format.
  #
  # @param output [String] command output to parse
  # @return [Hash<String, String>]
  def self.parse_colon_kv(output)
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

  # @see PuppetX::Ipmi::Provider::Base.parse_colon_kv
  def parse_colon_kv(output)
    self.class.parse_colon_kv(output)
  end

  # @return [Integer] IPMI channel for user management
  def channel
    @resource[:channel]
  end

  # @return [Integer] IPMI LAN channel for network/SNMP management
  def lan_channel
    @resource[:lan_channel]
  end
end
