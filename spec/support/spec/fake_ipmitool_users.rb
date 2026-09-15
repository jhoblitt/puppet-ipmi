# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# A stand-in `ipmitool` executable for specs that run the real ipmi_user
# ipmitool provider through a Puppet transaction.  It keeps a BMC's user
# table in files, per slot and channel, and answers `channel info`, `user
# list` and `channel getaccess` from them.  The writes the provider sends
# (names, privileges, channel access, enable and disable) change that state,
# so a second run sees what the first one wrote.  It records each command
# line it runs, and refuses one whose options are not ended with `--`.
class FakeIpmitoolUsers
  READS = ['user list', 'channel getaccess', 'channel info', 'user test'].freeze
  PRIVILEGES = { 1 => 'CALLBACK', 2 => 'USER', 3 => 'OPERATOR', 4 => 'ADMINISTRATOR', 5 => 'OEM', 15 => 'NO ACCESS' }.freeze

  attr_reader :dir

  # @param users [Array<Array>, Hash{Integer => Array<Array>}] `[id, name,
  #   privilege]` per slot, with the privilege as `user list` prints it
  #   (e.g. 'ADMINISTRATOR', 'NO ACCESS'); a Hash gives each channel its own
  # @param enable_status [String, nil, Hash{Integer => String, nil}] the
  #   `Enable Status` of every named slot, or of each slot; nil omits the
  #   line, as ipmitool before 1.8.18 does.  A named slot a Hash leaves out
  #   reports `enabled`.  An empty slot reports `disabled` when the BMC
  #   reports enabled or disabled, else the same.  `user enable` and `user
  #   disable` change only an enabled or disabled one.
  # @param lan_channels [Array<Integer>, nil] channels `channel info` reports
  #   as 802.3 LAN; the channels of `users`, or 1, when nil
  # @param refuse_priv [Symbol, nil] `:while_disabled` makes `user priv <id>`
  #   fail until `user enable <id>` has run, as on BMCs that refuse
  #   permission changes on a disabled account; `:always` makes it fail
  # @param reachable [Boolean] false makes every command fail as it does
  #   when ipmitool cannot reach the BMC
  # @param failing [Array<String>] commands that fail, each matched as a
  #   prefix of the command line (e.g. 'channel setaccess')
  def initialize(users, enable_status: 'enabled', lan_channels: nil, refuse_priv: nil, reachable: true, failing: [])
    @dir = Dir.mktmpdir
    @refuse_priv = refuse_priv
    @reachable = reachable
    @failing = failing
    FileUtils.mkdir_p(state)
    tables = users.is_a?(Hash) ? users : { 1 => users }
    (lan_channels || tables.keys).each { |channel| put("lan_#{channel}", '802.3 LAN') }
    load_tables(tables, enable_status)
    File.write(executable, script)
    File.chmod(0o755, executable)
  end

  # @return [String] path of the fake `ipmitool`
  def executable
    File.join(dir, 'ipmitool')
  end

  # Put the fake first on PATH.
  #
  # @return [void]
  def activate
    @old_path = ENV.fetch('PATH', nil)
    ENV['PATH'] = [dir, @old_path].compact.join(File::PATH_SEPARATOR)
  end

  # Restore PATH if #activate changed it, and remove the fake.
  #
  # @return [void]
  def cleanup
    ENV['PATH'] = @old_path if defined?(@old_path)
    FileUtils.rm_rf(dir)
  end

  # @return [Array<String>] every command line, arguments joined by spaces
  def calls
    log = File.join(dir, 'calls.log')
    return [] unless File.exist?(log)

    File.readlines(log, chomp: true)
  end

  # @return [Array<String>] the command lines that change BMC state
  def writes
    calls.reject { |c| c.start_with?(*READS) }
  end

  # @return [Array<String>] the lines `user set password` and `user test`
  #   read from stdin, and the lines of every `exec` batch file
  def secret_input
    log = File.join(dir, 'secrets.log')
    return [] unless File.exist?(log)

    File.readlines(log, chomp: true)
  end

  # @param id [Integer]
  # @param channel [Integer]
  # @return [Hash] the slot's name, privilege on the channel as `user list`
  #   prints it, and Enable Status (nil when the BMC omits it)
  def slot(id, channel = 1)
    { name: get("name_#{id}"), priv: get("priv_#{channel}_#{id}") || 'NO ACCESS', status: get("status_#{id}") }
  end

  private

  def state
    File.join(dir, 'state')
  end

  def put(name, value)
    File.write(File.join(state, name), "#{value}\n")
  end

  def get(name)
    path = File.join(state, name)
    File.read(path).chomp if File.exist?(path)
  end

  def load_tables(tables, enable_status)
    ids = tables.values.flatten(1).map(&:first).uniq.sort
    File.write(File.join(state, 'ids'), ids.map { |id| "#{id}\n" }.join)
    tables.each do |channel, list|
      list.each do |id, name, priv|
        put("name_#{id}", name)
        put("priv_#{channel}_#{id}", priv)
      end
    end
    ids.each do |id|
      status = status_for(enable_status, id, get("name_#{id}").to_s.empty?)
      put("status_#{id}", status) unless status.nil?
    end
  end

  def status_for(enable_status, id, empty)
    return enable_status[id] if enable_status.is_a?(Hash) && enable_status.key?(id)

    status = enable_status.is_a?(Hash) ? 'enabled' : enable_status
    (empty && %w[enabled disabled].include?(status)) ? 'disabled' : status
  end

  # Uses only shell builtins, so it runs with nothing else on PATH.
  def script
    unreachable = ''
    unreachable = "echo 'Error: Unable to establish IPMI v2 / RMCP+ session'; exit 1" unless @reachable
    <<~SH
      #!/bin/sh
      log='#{dir}/calls.log'
      s='#{state}'
      [ "$1" = -- ] || { echo "fake ipmitool: options not ended with -- in: $*"; exit 2; }
      shift
      echo "$*" >> "$log"
      #{unreachable}
      #{failing_checks}
      emit() { while IFS= read -r line; do printf '%s\\n' "$line"; done < "$1"; }
      record_secret() { while IFS= read -r line; do printf '%s\\n' "$line" >> '#{dir}/secrets.log'; done; }
      get() { v=$2; [ -f "$s/$1" ] && IFS= read -r v < "$s/$1"; }
      put() { printf '%s\\n' "$2" > "$s/$1"; }
      privilege() { case "$1" in #{PRIVILEGES.map { |n, p| "#{n}) v='#{p}' ;;" }.join(' ')} *) v="Unknown ($1)" ;; esac; }
      user_list() {
        printf 'ID  Name             Callin  Link Auth  IPMI Msg   Channel Priv Limit\\n'
        while IFS= read -r id; do
          get "name_$id" ''; name=$v; get "priv_$1_$id" 'NO ACCESS'
          printf '%-4d%-17s%-8s%-11s%-11s%s\\n' "$id" "$name" true false true "$v"
        done < "$s/ids"
      }
      getaccess() {
        n=0; while IFS= read -r id; do n=$((n + 1)); done < "$s/ids"
        printf 'Maximum User IDs     : %s\\nEnabled User IDs     : 2\\n' "$n"
        while IFS= read -r id; do
          [ -n "$2" ] && [ "$2" != "$id" ] && continue
          get "name_$id" ''; printf '\\nUser ID              : %s\\nUser Name            : %s\\n' "$id" "$v"
          get "priv_$1_$id" 'NO ACCESS'; printf 'Privilege Level      : %s\\n' "$v"
          get "status_$id" ''; [ -n "$v" ] && printf 'Enable Status        : %s\\n' "$v"
        done < "$s/ids"
      }
      set_status() { get "status_$1" ''; case "$v" in enabled|disabled) put "status_$1" "$2" ;; esac; }
      case "$1 $2" in
        'channel info')
          if [ -f "$s/lan_$3" ]; then printf 'Channel 0x%x info:\\n  Channel Medium Type   : 802.3 LAN\\n' "$3"
          else printf 'IPMI command failed: Invalid data field in request\\nUnable to Get Channel Info\\n' >&2; exit 1; fi ;;
        'user list') user_list "$3" ;;
        'channel getaccess') getaccess "$3" "$4" ;;
        'channel setaccess')
          ch=$3; id=$4
          for arg in "$@"; do case "$arg" in privilege=*) privilege "${arg#privilege=}"; put "priv_${ch}_$id" "$v" ;; esac; done ;;
        'user priv') #{refuse_priv_check}; privilege "$4"; put "priv_$5_$3" "$v" ;;
        'user enable') set_status "$3" enabled ;;
        'user disable') set_status "$3" disabled ;;
        'user test') record_secret ;;
        'user set')
          case "$3" in
            name) put "name_$4" "$5" ;;
            password) record_secret ;;
          esac ;;
      esac
      [ "$1" = exec ] && record_secret < "$2"
      exit 0
    SH
  end

  def failing_checks
    @failing.map { |prefix| "case \"$*\" in '#{prefix}'*) echo '#{prefix} failed'; exit 1 ;; esac" }.join("\n")
  end

  def refuse_priv_check
    refusal = '{ echo "Set User Access command failed (user $3)"; exit 1; }'
    case @refuse_priv
    when :while_disabled
      'enabled=; while IFS= read -r line; do [ "$line" = "user enable $3" ] && enabled=1; done < "$log"; ' \
      "[ -n \"$enabled\" ] || #{refusal}"
    when :always then refusal
    else ':'
    end
  end
end
