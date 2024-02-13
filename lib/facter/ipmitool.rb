#!/usr/bin/env ruby
# frozen_string_literal: true

Facter.add(:ipmitool, type: :aggregate) do
  # https://puppet.com/docs/puppet/latest/fact_overview.html
  confine kernel: 'Linux'
  confine is_virtual: false
  # TODO: consider confining based on which
  # this has the side affect that the ipmitool fact and ipmitool_mc_info facts would be Nil
  # if ipmi is not present instead of the curent values of
  # ipmitool: {"fru"=>{}, "mc_info"=>{"IPMI_Puppet_Service_Recommend"=>"stopped"}}
  # ipmitool_mc_info: {"IPMI_Puppet_Service_Recommend"=>"stopped"}
  # confine do
  #   Facter::Util::Resolution.which('ipmitool')
  # end

  ipmitool_present = Facter::Util::Resolution.which('ipmitool')
  chunk(:fru) do
    retval = { fru: {} }
    if ipmitool_present
      ipmitool_output = Facter::Util::Resolution.exec('ipmitool fru print 0 2>/dev/null')
      ipmitool_output.each_line do |line|
        next unless line.include?(':')

        info = line.split(':', 2)
        next if info[1].strip.empty?

        key = info[0].strip.tr("\s", '_').downcase
        retval[:fru][key] = info[1].strip
      end
    end
    retval
  end

  chunk(:mc_info) do
    retval = { mc_info: { 'IPMI_Puppet_Service_Recommend' => 'stopped' } }
    if ipmitool_present
      ipmitool_output = Facter::Util::Resolution.exec('ipmitool mc info 2>/dev/null')

      ipmitool_output.each_line do |line|
        info = line.split(':')
        retval[:mc_info][info[0].strip] = info[1].strip if info.length == 2 && (info[1].strip != '')
      end
      retval[:mc_info]['IPMI_Puppet_Service_Recommend'] = 'running' if retval[:mc_info].fetch('Device Available', 'no') == 'yes'
    end
    retval
  end
end
