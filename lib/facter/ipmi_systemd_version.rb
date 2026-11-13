# frozen_string_literal: true

# Major version of systemd, reported only where systemd is the init system:
# /run/systemd/system is the path sd_booted(3) tests for.
Facter.add(:ipmi_systemd_version) do
  confine kernel: 'Linux'
  confine { File.exist?('/run/systemd/system') }

  setcode do
    output = Facter::Core::Execution.execute('systemctl --version', on_fail: '')
    output[%r{\Asystemd (\d+)}, 1]
  end
end
