# frozen_string_literal: true

# Reads an `ipmitool exec` batch file the way ipmitool does (ipmi_exec_main
# in src/ipmishell.c, the same in 1.8.18 and 1.8.19), returning the argv of
# each command it would run.  Each line is a C string, cut at its first `#`;
# whitespace inside quotes becomes `~`; the line is trimmed and split on
# spaces; and a word that starts with a quote loses it, ends at the next
# one, and has every `~` turned into a space.
module IpmitoolExecFile
  SPACE = " \t\n\v\f\r"

  # @param content [String]
  # @return [Array<Array<String>>]
  def self.parse(content)
    content.each_line.filter_map { |line| parse_line(line) }
  end

  def self.parse_line(line)
    text = mark_quoted_spaces(line[%r{\A[^\0#]*}])
    words = text.sub(%r{[#{SPACE}]+\z}, '').sub(%r{\A[#{SPACE}]+}, '').split(%r{ +}).reject(&:empty?)
    words.map { |word| unquote(word) } unless words.empty?
  end

  def self.mark_quoted_spaces(text)
    chars = text.chars
    i = 0
    while i < chars.length
      if ['"', "'"].include?(chars[i])
        quote = chars[i]
        i += 1
        while i < chars.length && chars[i] != quote
          chars[i] = '~' if SPACE.include?(chars[i])
          i += 1
        end
      end
      i += 1
    end
    chars.join
  end

  def self.unquote(word)
    quote = word[0]
    return word unless ['"', "'"].include?(quote)

    word[1..].split(quote, 2).first.to_s.tr('~', ' ')
  end
end
