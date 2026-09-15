# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/base'

# Base provider for IPMI backends that use the FreeIPMI `bmc-config` command.
class PuppetX::Ipmi::Provider::Freeipmi < PuppetX::Ipmi::Provider::Base
  # Keys whose values are secrets: user passwords, the SNMP community and
  # the RMCP+ keys.
  SECRET_KEYS = 'Password|Password20|Community_String|K_g|K_r'

  # Output lines that carry a secret, and what replaces each: a checked-out
  # secret key, and the value ipmi-config's validation names when it
  # refuses one (ipmi_config_sections_validate_keyvalue_inputs in
  # ipmi-config-section.c: "Invalid value '%s' for key '%s' ...", and the
  # like).
  ECHOES = {
    %r{^(\s*(?:##\s*)?(?:#{SECRET_KEYS}))\s.*$} => '\1 [redacted]',
    %r{^(.*?[Vv]alue )'.*'( for key '(?:#{SECRET_KEYS})'.*)$} => "\\1'[redacted]'\\2",
  }.freeze

  # Name of the `commands` entry this provider executes.  Providers for other
  # ipmi-config front ends (e.g. ipmi-pef-config) override this.
  #
  # @return [Symbol]
  def self.config_command
    :bmcconfig
  end

  # Execute a bmc-config subcommand; a sensitive or scrubbed one fails with
  # its output scrubbed of the ECHOES lines and the `redact` values (see
  # Base.execute_scrubbed).
  #
  # @param argv [Array<String>] subcommand and arguments
  # @param failonfail [Boolean] whether to raise on non-zero exit
  # @param sensitive [Boolean] whether to redact the command in logs and
  #   scrub the output of a failure
  # @param redact [Array<String>] values to keep out of a failure's output
  # @param scrub [Boolean] scrub the output of a failure without redacting
  #   the command, for a read whose output may hold a secret
  # @return [Puppet::Util::Execution::ProcessOutput]
  def self.bmcconfig_exec(argv, failonfail: true, sensitive: false, redact: [], scrub: false)
    cmd = [command(config_command)] + Array(argv)
    execute_scrubbed(cmd, echoes: ECHOES, failonfail: failonfail, sensitive: sensitive, scrub: scrub, redact: redact)
  end

  # @see PuppetX::Ipmi::Provider::Freeipmi.bmcconfig_exec
  def bmcconfig_exec(argv, failonfail: true, sensitive: false, redact: [], scrub: false)
    self.class.bmcconfig_exec(argv, failonfail: failonfail, sensitive: sensitive, redact: redact, scrub: scrub)
  end

  # Build the bmc-config argv for writing one key/value pair.
  #
  # FreeIPMI's --key-pair parser keeps only the first whitespace-separated
  # word of the value, so a value containing whitespace is silently truncated.
  # The value is deliberately omitted from the error message because it may be
  # a password or community string.
  #
  # @return [Array<String>]
  def self.bmc_config_set_argv(section, key, value, channel: nil)
    raise Puppet::Error, "#{section}:#{key}: freeipmi cannot store a value containing whitespace" if value.to_s.match?(%r{\s})

    argv = ['--commit', '--key-pair', "#{section}:#{key}=#{value}"]
    argv += ['--lan-channel-number', channel.to_s] if channel
    argv
  end

  # Write a key/value pair to a bmc-config section.
  #
  # @return [void]
  def self.bmc_config_set(section, key, value, channel: nil, sensitive: false)
    bmcconfig_exec(bmc_config_set_argv(section, key, value, channel: channel), sensitive: sensitive)
  end

  # Run `bmc-config <action> --filename` with one secret key/value pair, so
  # the value never goes on the command line, where any local user can read
  # it from ps or /proc/<pid>/cmdline.
  #
  # The config file parser (ipmi_config_parse in ipmi-config-parse.c, the
  # same from FreeIPMI 1.6.1 to 1.6.20) reads each line as a C string, so a
  # NUL ends it, and takes the word after the key, split on space, tab or
  # newline, as the value.  It has no quoting, escaping or continuation, and
  # a `#` starts a comment only as a line's first word, which here is always
  # the key.  So a value containing whitespace or a NUL would be silently
  # cut short, by --diff as well as --commit, and is refused, without
  # echoing it; every other byte is carried unchanged.
  #
  # @param action [String] '--commit' or '--diff'
  # @param extra_argv [Array<String>] arguments after the file
  # @return [Puppet::Util::Execution::ProcessOutput]
  def self.bmc_config_secret(action, section, key, value, extra_argv: [], failonfail: true)
    check_secret(section, key, value)

    with_secret_file("Section #{section}\n\t#{key}\t#{value}\nEndSection\n") do |path|
      bmcconfig_exec([action, '--filename', path] + extra_argv, failonfail: failonfail, sensitive: true, redact: [value.to_s])
    end
  end

  # Refuse, without echoing it, a value bmc_config_secret cannot carry.
  #
  # @return [void]
  def self.check_secret(section, key, value)
    raise Puppet::Error, "#{section}:#{key}: freeipmi cannot store a value containing whitespace or a NUL byte" if value.to_s.match?(%r{[\s\0]})
  end

  # Read a key from a bmc-config section.
  #
  # @param section [String] section name
  # @param key [String] field name
  # @param channel [Integer, nil] optional LAN channel number
  # @return [String, nil]
  def bmc_config_get(section, key, channel: nil)
    section_cache(section, channel: channel)[key.to_s]
  end

  # Write a key/value pair to a bmc-config section.
  #
  # @param section [String] section name
  # @param key [String] field name
  # @param value [String] field value
  # @param channel [Integer, nil] optional LAN channel number
  # @return [void]
  def bmc_config_set(section, key, value, channel: nil, sensitive: false)
    bmcconfig_exec(self.class.bmc_config_set_argv(section, key, value, channel: channel), sensitive: sensitive)
  end

  private

  # Cache parsed bmc-config section data per section/channel.  A failed
  # checkout's output is scrubbed, since the section may hold a secret.
  #
  # @param section [String] section name
  # @param channel [Integer, nil] optional LAN channel number
  # @return [Hash<String, String>]
  def section_cache(section, channel: nil)
    @section_cache ||= {}
    cache_key = [section.to_s, channel]
    argv = ['--checkout', '--section', section.to_s]
    argv += ['--lan-channel-number', channel.to_s] if channel
    @section_cache[cache_key] ||= parse_section(bmcconfig_exec(argv, scrub: true))
  end

  # Parse bmc-config section output into a hash.
  #
  # @param output [String]
  # @return [Hash<String, String>]
  def parse_section(output)
    result = {}
    return result if output.nil? || output.empty?

    output.each_line do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?('#', 'Section', 'EndSection')
      next unless stripped =~ %r{^(\S+)\s+(.+)$}

      k = Regexp.last_match(1)
      v = Regexp.last_match(2).strip
      result[k] = v
    end
    result
  end

  # Invalidate cached data for a bmc-config section.
  #
  # @param section [String] section name
  # @param channel [Integer, nil] optional LAN channel number
  # @return [void]
  def invalidate_section_cache!(section, channel: nil)
    return unless defined?(@section_cache)

    @section_cache.delete([section.to_s, channel])
  end
end
