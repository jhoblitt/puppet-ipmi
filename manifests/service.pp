class ipmi::service {
  service{ 'ipmi':
    ensure      => running,
    hasstatus   => true,
    hasrestart  => true,
    enable      => true,
    require     => Class['ipmi::install'],
  }
}
