# frozen_string_literal: true

require_relative "chat_store"
require_relative "conversation_runtime"
require_relative "application_chat_service"
require "securerandom"

module SoulCore
  class ChatCommand
    def initialize(
      argv:,
      root: Dir.pwd,
      input: $stdin,
      output: $stdout,
      env: ENV,
      runtime: nil,
      chat_service: nil
    )
      @argv = argv.dup
      @root = File.expand_path(root)
      @input = input
      @output = output
      @store = ChatStore.new(root: @root)
      @runtime = runtime || ConversationRuntime.new(
        root: @root,
        store: @store,
        env: env
      )
      @chat_service = chat_service || ApplicationChatService.new(
        root: @root,
        store: @store,
        runtime: @runtime
      )
    end

    def run
      return list_chats if flag?("--list") || flag?("list") || flag?("chats")
      return search_chats(value_after("--search")) if flag?("--search")
      return show_chat(value_after("--show")) if flag?("--show")
      return pin_chat(value_after("--pin")) if flag?("--pin")
      return unpin_chat(value_after("--unpin")) if flag?("--unpin")

      resume_id = value_after("--resume")
      message = remaining_message
      chat = resume_id ? @store.chat(resume_id) : nil
      raise ArgumentError, "Unknown chat id: #{resume_id}" if resume_id && !chat

      chat ||= @store.create_chat(initial_title: message.empty? ? nil : message[0, 60])

      if message.empty?
        interactive(chat.fetch("id"))
      else
        exchange(chat.fetch("id"), message)
      end
    rescue ArgumentError => error
      @output.puts "Chat error: #{error.message}"
      1
    end

    private

    def interactive(chat_id)
      @output.puts "Soul chat started: #{chat_id}"
      @output.puts "Type /exit to leave. Type /skills, /status, or /who for deterministic routes."

      loop do
        @output.print "You> "
        line = @input.gets
        break if line.nil?

        message = line.strip
        break if ["/exit", "exit", "quit", "/quit"].include?(message)

        message = "what skills do you have?" if message == "/skills"
        message = "status" if message == "/status"
        message = "who are you?" if message == "/who"
        next if message.empty?

        exchange(chat_id, message)
      end

      @output.puts "Soul chat closed: #{chat_id}"
      0
    end

    def exchange(chat_id, message)
      exchange = @chat_service.send(
        chat_id: chat_id,
        message: message,
        request_id: "cli:#{SecureRandom.uuid}",
        interface: "cli"
      )
      unless exchange.fetch("ok")
        @output.puts "Soul chat error: #{exchange['reason']}"
        return 1
      end

      @output.puts "Soul> #{exchange.dig('assistant_message', 'content')}"
      0
    end

    def list_chats
      chats = @store.list_chats
      if chats.empty?
        @output.puts "No Soul chats yet."
        return 0
      end

      chats.each do |chat|
        pin = chat["pinned"] ? "*" : " "
        @output.puts "#{pin} #{chat['id']} #{chat['updated_at']} #{chat['title']}"
      end
      0
    end

    def search_chats(query)
      unless query && !query.strip.empty?
        @output.puts "Chat error: --search requires text"
        return 1
      end

      results = @store.search(query)
      if results.empty?
        @output.puts "No chats matched #{query.inspect}."
        return 0
      end

      results.each do |chat|
        @output.puts "#{chat['id']} #{chat['updated_at']} #{chat['title']}"
      end
      0
    end

    def show_chat(chat_id)
      unless chat_id && !chat_id.strip.empty?
        @output.puts "Chat error: --show requires a chat id"
        return 1
      end

      chat = @store.chat(chat_id)
      unless chat
        @output.puts "Chat error: unknown chat id #{chat_id}"
        return 1
      end

      @output.puts "# #{chat['title']}"
      @output.puts "id: #{chat['id']}"
      @output.puts "created_at: #{chat['created_at']}"
      @output.puts "updated_at: #{chat['updated_at']}"
      @output.puts

      @store.messages(chat_id).each do |message|
        @output.puts "#{message['role']}> #{message['content']}"
      end
      0
    end

    def pin_chat(chat_id)
      @store.pin(chat_id)
      @output.puts "Pinned chat #{chat_id}"
      0
    end

    def unpin_chat(chat_id)
      @store.unpin(chat_id)
      @output.puts "Unpinned chat #{chat_id}"
      0
    end

    def flag?(name)
      @argv.include?(name)
    end

    def value_after(name)
      index = @argv.index(name)
      return nil unless index

      @argv[index + 1]
    end

    def remaining_message
      skip_next = false
      parts = []

      @argv.each_with_index do |argument, index|
        if skip_next
          skip_next = false
          next
        end

        if ["--resume", "--search", "--show", "--pin", "--unpin"].include?(argument)
          skip_next = true
          next
        end

        next if argument.start_with?("--")
        next if index.zero? && argument == "chat"

        parts << argument
      end

      parts.join(" ").strip
    end
  end
end
