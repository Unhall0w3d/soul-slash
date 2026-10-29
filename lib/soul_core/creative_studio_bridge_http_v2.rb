# frozen_string_literal: true
require_relative 'creative_studio_bridge_v2'
require_relative 'roster_dashboard_runtime'
module SoulCore
  # Transport remains a fixed loopback URL. No arbitrary operation/path or
  # credential is supplied by a model, the browser or a creative brief.
  class CreativeStudioBridgeClientV2 < RosterDashboardRuntime
    def initialize(**args);super(store:nil,**args);end
    def call(action,body)
      raise ArgumentError,'creative action' unless %w[prepare submit status cancel].include?(action)
      token=@key_reader.call
      send(:post,'/internal/creative/v2/'+action,body,token,80,{})
    ensure
      token&.clear
    end
    private
    def coordinator_port = 4567
  end

  module CreativeStudioBridgeHttpV2
    ROUTES=%w[prepare submit status cancel].to_h{|name|['/internal/creative/v2/'+name,name]}.freeze
    def self.call(application,method:,target:,headers:,body:,key_reader:-> { RosterDashboardRuntime.new(store:nil).send(:read_key) })
      raise ArgumentError,'route' unless ROUTES.key?(target)
      respond=->(status,data){application.send(:json_response,status,data)}
      return respond.call(403,{'error'=>'Origin not permitted'}) if headers.key?('origin')||headers['host']!='127.0.0.1:4567'
      return respond.call(405,{'error'=>'POST required'}) unless method=='POST'
      token=key_reader.call
      valid=application.send(:secure_compare,headers['authorization'],'Bearer '+token)
      return respond.call(401,{'error'=>'Authentication required'}) unless valid
      raise ArgumentError,'request bound' unless body.is_a?(String)&&body.bytesize.between?(1,32*1024)
      data=ContinuityLab.parse(body);action=ROUTES.fetch(target)
      expected={'prepare'=>%w[conversation_id preview],'submit'=>%w[approval_digest conversation_id id],'status'=>%w[conversation_id id],'cancel'=>%w[conversation_id id]}.fetch(action)
      raise ArgumentError,'exact scope' unless data.is_a?(Hash)&&data.keys.sort==expected
      result=application.send(:creative_bridge_v2).public_send(action,**data.transform_keys(&:to_sym))
      respond.call(200,result)
    rescue CreativeStudioBridgeV2::Refused => error
      respond.call(200,{'state'=>'blocked_for_human_review','refused'=>true,'message'=>error.message.byteslice(0,1024)})
    rescue ArgumentError,KeyError,ContinuityLab::Error
      respond.call(422,{'error'=>'Creative action refused; scope, availability or retained state needs review. No automatic retry.'})
    ensure
      token&.clear
    end
  end
end
