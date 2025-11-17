# frozen_string_literal: true

module VzekcVerlosung
  # Utility module for extracting lottery packet titles from markdown content
  #
  # Packet posts have titles in the format: "# Paket N: Title Text"
  # This module provides methods to extract the title and validate its presence
  module TitleExtractor
    # Extract the title from packet post markdown
    #
    # @param raw [String] The raw markdown content of the post
    # @return [String, nil] The extracted title without the "Paket N:" prefix, or nil if not found
    #
    # @example
    #   extract_title("# Paket 1: GPU Bundle\n\nDescription...")
    #   # => "GPU Bundle"
    def self.extract_title(raw)
      return nil if raw.blank?

      # Match heading: "# Paket N: Title" and extract everything after "Paket N:" on the SAME LINE
      # Use [ \t]* instead of \s* to avoid matching newlines
      match = raw.match(/^#\s+Paket\s+\d+:[ \t]*([^\n]+?)[ \t]*$/)
      return nil unless match

      title = match[1].strip
      (title.presence)
    end

    # Extract the packet number (ordinal) from packet post markdown
    #
    # @param raw [String] The raw markdown content of the post
    # @return [Integer, nil] The packet ordinal number, or nil if not found
    #
    # @example
    #   extract_packet_number("# Paket 5: GPU Bundle")
    #   # => 5
    def self.extract_packet_number(raw)
      return nil if raw.blank?

      match = raw.match(/^#\s+Paket\s+(\d+):/)
      match ? match[1].to_i : nil
    end

    # Check if the post has a valid packet title heading
    #
    # @param raw [String] The raw markdown content of the post
    # @return [Boolean] true if a valid packet title heading exists
    def self.has_title?(raw)
      return false if raw.blank?

      raw.match?(/^#\s+Paket\s+\d+:/)
    end

    # Extract title for Abholerpaket (special case: "# Paket 0: Title")
    #
    # @param raw [String] The raw markdown content of the post
    # @return [String, nil] The extracted title, or nil if not found
    def self.extract_abholerpaket_title(raw)
      return nil if raw.blank?

      match = raw.match(/^#\s+Paket\s+0:\s*(.+)$/)
      match ? match[1].strip : nil
    end
  end
end
