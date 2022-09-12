configure_beaker do |host|
  install_module_from_forge_on(host, 'puppet/epel', '> 4 < 5')
end
