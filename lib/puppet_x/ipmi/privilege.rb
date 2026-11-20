# frozen_string_literal: true

require 'puppet_x/ipmi'

module PuppetX
  module Ipmi
    # The privilege levels an `ipmi_user` may name, as manifest words and the
    # IPMI numbers they stand for.
    #
    # Design rationale: the words are the manifest API and are fixed here, so a
    # backend's own spelling (ipmitool's `NO ACCESS`, freeipmi's `No_Access`)
    # never reaches a manifest.  The IPMI numbers are the wire values the
    # providers write.  OEM (5) is left out: the type does not offer it.
    module Privilege
      # @return [Hash<Symbol, Integer>] manifest word to IPMI privilege number
      NAMES = {
        ADMIN: 4,
        OPERATOR: 3,
        USER: 2,
        CALLBACK: 1,
        NOACCESS: 15,
      }.freeze

      # @param word [Symbol, String] a manifest word
      # @return [Integer] its IPMI privilege number
      def self.number(word)
        NAMES.fetch(word.to_s.upcase.to_sym)
      end
    end
  end
end
