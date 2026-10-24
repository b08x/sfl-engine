# frozen_string_literal: true

# File builders for the JSON records steps. Conversation text is built from
# the feature's own quoted pieces, and each file is written to a tmp directory.

require "fileutils"
require "json"
require "sfl"

module JsonRecordsSteps
  # Builds the text of the feature's files and writes them to disk.
  module Files
    # A message clause: a quoted text, an optional (human|assistant|empty) mark,
    # no "text" key, a null text, or a number text.
    MESSAGE = /no "text" key|text null|whose "text" is (\d+)|"([^"]*)"(?: \((human|assistant|empty)\))?/

    def jr_dir = (@jr_dir ||= Dir.mktmpdir("json-records-steps"))

    def jr_state(name) = ((@jr_files ||= {})[name] ||= { parts: [], truncated: false })

    # Returns the file's full text. Parts are joined with ", " unless glued.
    def jr_text(name)
      state = jr_state(name)
      return state[:raw] if state[:raw]

      out = +"["
      state[:parts].each_with_index do |part, index|
        out << ", " if index.positive? && !part[:glue]
        @jr_stray_offset = out.bytesize if part[:stray]
        out << part[:text]
      end
      out << "]" unless state[:truncated]
      out
    end

    def jr_path(name)
      path = File.join(jr_dir, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, jr_text(name))
      path
    end

    def jr_ref(name)
      path = jr_path(name)
      SFL::Core::Refs::FileRefBuilder.call(path, source_id: path)
    end

    # Adds one conversation record. A "cut off" clause is a record that ends after the first message's opening brace.
    def jr_add_conversation(name, uuid, clause)
      if clause.include?("cut off")
        jr_add_raw(name, %({"uuid": "#{uuid}", "chat_messages": [{), truncated: true)
        return
      end
      messages = clause.to_enum(:scan, MESSAGE).map { Regexp.last_match }.map { |match| jr_message(match) }
      jr_add_part(name, JSON.generate({ "uuid" => uuid, "name" => "Chat", "chat_messages" => messages }))
    end

    def jr_message(match)
      return { "sender" => "human" } if match[0] == 'no "text" key'
      return { "sender" => "human", "text" => nil } if match[0] == "text null"
      return { "sender" => "human", "text" => match[1].to_i } if match[1]

      sender = (match[3] == "assistant") ? "assistant" : "human"
      { "sender" => sender, "text" => match[2], "created_at" => "2024-06-15T18:35:00Z" }
    end

    def jr_add_part(name, text, **options) = jr_state(name)[:parts] << { text: }.merge(options)

    def jr_add_raw(name, text, truncated: false)
      jr_add_part(name, text)
      jr_state(name)[:truncated] = true if truncated
    end

    # Splits "conversation "uuid" clause, conversation "uuid" clause" into segments and adds each.
    def jr_add_segments(name, text)
      text.split(/(?=conversation ")/).each do |segment|
        next unless (match = /\Aconversation "([^"]+)"(.*)\z/m.match(segment))

        jr_add_conversation(name, match[1], match[2])
      end
    end

    def jr_file_size(name) = File.size(jr_path(name))
  end
end
