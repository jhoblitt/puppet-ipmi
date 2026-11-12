# frozen_string_literal: true

# Reads a config file the way FreeIPMI's `bmc-config --filename` does
# (ipmi_config_parse in ipmi-config/ipmi-config-parse.c, unchanged from
# 1.6.1 to 1.6.20): each line is a C string, split on space, tab and newline;
# a line whose first word starts with `#` is a comment; a key's value is the
# word after it.
module FreeipmiConfigFile
  # @param content [String]
  # @return [Hash{String => Hash{String => String}}] values by section and key
  def self.parse(content)
    sections = {}
    section = nil
    content.each_line do |line|
      words = line[%r{\A[^\0]*}].split(%r{[ \t\n]}).reject(&:empty?)
      next if words.empty? || words.first.start_with?('#')

      case words.first.downcase
      when 'section' then section = sections[words[1]] = {}
      when 'endsection' then section = nil
      else section[words.first] = words[1] || ''
      end
    end
    sections
  end
end
