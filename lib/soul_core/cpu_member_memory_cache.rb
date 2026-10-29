# frozen_string_literal: true
require 'digest'
require_relative 'cpu_member_conversation_cache'
module SoulCore
  class CpuMemberMemoryCache < CpuMemberConversationCache
    def request(key,*args,**controls)
      payload=args[2]
      bound=[key,Digest::SHA256.hexdigest(payload.fetch('messages').first.fetch('content'))] if args[1]=='/v1/chat/completions'
      super(bound||key,*args,**controls)
    end
  end
end
