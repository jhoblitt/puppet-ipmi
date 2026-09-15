# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/base'

# Base provider for IPMI backends that use the `ipmitool` command.
class PuppetX::Ipmi::Provider::Ipmitool < PuppetX::Ipmi::Provider::Base
  # Output lines that carry a secret, and what replaces each: the community
  # `lan set` echoes and the current one `lan print` reports.  The whole line
  # goes, because ipmitool may echo a value altered: `lan set` cuts a
  # community to 18 bytes.  ipmitool 1.8.19
  # echoes no password: `user set password`, `user test` and `exec` report
  # only the user id, the 16 or 20 size argument, or a line number.
  ECHOES = {
    %r{^Setting LAN SNMP Community String to .*$} => 'Setting LAN SNMP Community String to [redacted]',
    %r{^SNMP Community String\s*:.*$} => 'SNMP Community String : [redacted]',
  }.freeze

  # Execute an ipmitool subcommand; a sensitive or scrubbed one fails with
  # its output scrubbed of the ECHOES lines and the `redact` values (see
  # Base.execute_scrubbed).
  #
  # ipmitool parses its options with getopt(3) and no leading `+` (ipmi_main
  # in lib/ipmi_main.c, 1.8.18 and 1.8.19), so glibc's getopt permutes argv
  # and takes an argument anywhere that starts with `-`, such as a
  # username, as an option.  `--` ends the options before the subcommand.
  #
  # @param argv [Array<String>] subcommand and arguments
  # @param failonfail [Boolean] whether to raise on non-zero exit
  # @param sensitive [Boolean] whether to redact the command in logs and
  #   scrub the output of a failure
  # @param stdinfile [String, nil] path of a file to feed on stdin
  # @param redact [Array<String>] values to keep out of a failure's output
  # @param scrub [Boolean] scrub the output of a failure without redacting
  #   the command, for a read whose output holds a secret
  # @return [Puppet::Util::Execution::ProcessOutput]
  def self.ipmitool_exec(argv, failonfail: true, sensitive: false, stdinfile: nil, redact: [], scrub: false)
    cmd = [command(:ipmitool), '--'] + Array(argv)
    execute_scrubbed(cmd, echoes: ECHOES, failonfail: failonfail, sensitive: sensitive, scrub: scrub, redact: redact, stdinfile: stdinfile)
  end

  # @see PuppetX::Ipmi::Provider::Ipmitool.ipmitool_exec
  def ipmitool_exec(argv, failonfail: true, sensitive: false, stdinfile: nil, redact: [], scrub: false)
    self.class.ipmitool_exec(argv, failonfail: failonfail, sensitive: sensitive, stdinfile: stdinfile, redact: redact, scrub: scrub)
  end

  # Quote a secret as one argument of an `ipmitool exec` batch line, so it
  # reaches ipmitool without going on its command line.  The parser
  # (ipmi_exec_main in src/ipmishell.c, the same in 1.8.18 and 1.8.19)
  # reads each line as a C string, cuts it at the first `#`, splits it on
  # spaces, and inside quotes turns other whitespace and `~` into spaces.
  # So a value is written bare when it has no whitespace, quotes or `#`,
  # otherwise quoted with the quote it lacks, and refused, without echoing
  # it, when neither form survives.
  #
  # @param value [String]
  # @param what [String] what the value is, for the error message
  # @return [String]
  def self.exec_token(value, what)
    return value unless value.match?(%r{[\s'"#\0]})

    quote = "'"
    quote = '"' unless value.include?('"')
    if value.match?(%r{[#~\t\n\r\v\f\0]}) || value.include?(quote)
      raise Puppet::Error, "ipmitool cannot pass #{what} containing #, a tab or newline, a NUL byte, both quote " \
                           'characters, or ~ together with a space or quote, without putting it on the command line'
    end

    "#{quote}#{value}#{quote}"
  end

  # Parse `ipmitool lan print <channel>` output into key-value pairs.
  #
  # @return [Hash<String, String>]
  def parse_lan_print
    return @parse_lan_print if defined?(@parse_lan_print)

    output = ipmitool_exec(['lan', 'print', lan_channel.to_s], scrub: true)
    @parse_lan_print = parse_colon_kv(output)
  end

  # Invalidate cached `ipmitool lan print` data.
  #
  # @return [void]
  def invalidate_lan_print_cache!
    remove_instance_variable(:@parse_lan_print) if defined?(@parse_lan_print)
  end
end
