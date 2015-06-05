# Fact: bmc_lan_conf
#
# Purpose: get IP of BMC
#
# Resolution:
#   Uses freeipmi query tool
#   bmc-config --checkout -e Lan_Conf:IP_Address
#   Section Lan_Conf
#           ## Give valid IP address
#           IP_Address                                    192.168.168.17
#   EndSection
#
# Caveats:
#   Needs freeipmi. If you find a better way using OpenIPMI
# please tell me
#
# Notes:
#   None
Facter.add(:bmc_lan_conf, :timeout => 5) do
  confine :kernel => "Linux"
  confine :is_virtual => "false"
  confine :kmod_isloaded_ipmi_si => "true"
  setcode do
    if Facter::Util::Resolution.which('bmc-config')
      output = Facter::Util::Resolution.exec("bmc-config --checkout --section Lan_Conf --disable-auto-probe").lines.find_all { |l| l =~ /^\s+[^#]/}
      if ! output.empty?
        Hash[output.map { |e| e.split }]
      end
    end
  end
end

