# Fact: kmod_isloaded_ipmi_si
#
# Purpose: report kernel module status
#
# Resolution:
#   Uses lsmod to list kernel modules
#
Facter.add(:kmod_isloaded_ipmi_si, :timeout => 5) do
  confine :kernel => "Linux"
  if Facter::Util::Resolution.which('lsmod')
    lsmod_output = Facter::Util::Resolution.exec('lsmod')
    if lsmod_output[0]
      is_loaded = !!(/^ipmi_si\s/.match(lsmod_output))
      setcode do
        is_loaded
      end
    else
      Facter.debug("Running lsmod didn't work out")
    end
  end
end
