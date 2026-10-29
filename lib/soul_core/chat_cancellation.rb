# frozen_string_literal: true

module SoulCore
  # Request-local cooperative signal. Only a runtime that has verified its own
  # cleanup may raise Confirmed; requesting Stop alone never proves release.
  module ChatCancellation
    class Confirmed < StandardError; end

    class Token
      def initialize
        @mutex = Mutex.new
        @requested = @sealed = false
      end

      def call = @mutex.synchronize { @requested }

      def request
        @mutex.synchronize do
          return false if @sealed
          @requested = true
        end
      end

      # Close the cancellation window before persisting a completed answer.
      # A Stop arriving after this point must not claim the answer was canceled.
      def seal
        @mutex.synchronize do
          @sealed = true
          @requested
        end
      end
    end
  end
end
