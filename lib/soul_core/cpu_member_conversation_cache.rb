# frozen_string_literal: true
module SoulCore
  # Service serializes requests. This holds one ephemeral cache identity, never KV
  # bytes. llama.cpp cache_prompt:false discards prefix matching for other owners.
  class CpuMemberConversationCache
    def initialize(owner);@owner=owner;@key=nil;end
    def invalidate;@key=nil;end
    def client(key)
      Bound.new(self,key)
    end
    def request(key,*args,deadline:,cancel:)
      method,path,payload=args
      return @owner.request(*args,deadline:deadline,cancel:cancel) unless path=='/v1/chat/completions'
      reuse=@key==key && @owner.status['state']=='loaded'
      invalidate
      result=@owner.request(method,path,payload.merge('cache_prompt'=>reuse,'id_slot'=>0),deadline:deadline,cancel:cancel)
      raise CpuMemberGateway::Refused,'CPU cache request canceled' if cancel.call
      @key=key
      result
    rescue StandardError
      invalidate;raise
    end
    class Bound
      def initialize(cache,key);@cache,@key=cache,key;end
      def request(*args,**kwargs)=@cache.request(@key,*args,**kwargs)
    end
  end
end
