ipmi::network { 'lan1':
  type        => 'static',
  ip          => '192.168.1.10',
  netmask     => '255.255.255.0',
  gateway     => '192.168.1.1',
  lan_channel => 1,
}
