# frozen_string_literal: true

# Namespace for helper code shared by the ipmi_* native types and providers.
#
# Design rationale: Puppet documents `puppet_x/<org>/<module>` as the place for
# module-supplied helpers.  Reopening `Puppet::Provider` or `Puppet::Util`
# risks colliding with Puppet itself, and `Puppet::Type` is a class, so it
# cannot serve as a namespace.
module PuppetX
  module Ipmi
    # @param value [Object] a value that may be wrapped in Sensitive
    # @return [Object] the wrapped value, or the value itself
    def self.unwrap(value)
      value.respond_to?(:unwrap) ? value.unwrap : value
    end

    module Provider
    end
  end
end
