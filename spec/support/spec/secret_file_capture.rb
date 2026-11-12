# frozen_string_literal: true

# Records a command a provider runs, with the mode and content of the file
# it reads its secret from, captured while the command runs (the provider
# removes the file afterwards).
module SecretFileCapture
  Call = Struct.new(:argv, :file, :mode, :content, keyword_init: true)

  # @param argv [Array<String>] the command's arguments
  # @param file [String, nil] path of the file holding the secret
  # @return [Call]
  def self.call(argv, file)
    return Call.new(argv: argv) if file.nil?

    Call.new(argv: argv, file: file, mode: File.stat(file).mode & 0o777, content: File.read(file))
  end
end
