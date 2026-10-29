require 'minitest/autorun'
require_relative '../lib/soul_core/roster_service_application'
require_relative '../lib/soul_core/shared_compute_service'
require_relative '../lib/soul_core/creative_render_guard'
class TelemetryDiagnosticTest < Minitest::Test
  def test_safe_classification_and_no_exception_text_leak
    d=SoulCore::TelemetryDiagnostic
    d::MESSAGES.each{|message,code|assert_equal code,d.code(SoulCore::GpuAccountingSnapshot::Unavailable.new(message))}
    assert_equal 'transport_timeout',d.code(Timeout::Error.new('secret'))
    assert_equal 'transport_error',d.code(Errno::ECONNREFUSED.new('secret'))
    assert_equal 'control_unavailable',d.code(RuntimeError.new('secret'))
    assert_equal 'http_refused',d::Refused.new('secret').code
  end
  def test_authenticated_route_preserves_code_but_not_raw_message
    backend=Object.new
    backend.define_singleton_method(:complete){|**_|raise 'not called'}
    backend.define_singleton_method(:creative_telemetry){|**_|raise SoulCore::GpuAccountingSnapshot::Unavailable,'incomplete accounting'}
    app=SoulCore::RosterServiceApplication.new(backend:backend,bearer_token:'a'*64)
    args={method:'POST',target:'/v1/soul/compute/telemetry',body:JSON.generate(handoff_id:'b'*32)}
    assert_equal 401,app.call(**args,headers:{}).status
    headers={'Authorization'=>"Bearer #{'a'*64}"}
    assert_equal 403,app.call(**args,headers:headers.merge('Origin'=>'foreign')).status
    r=app.call(**args,headers:headers)
    assert_equal 503,r.status
    assert_equal 'accounting_incomplete',JSON.parse(r.body).dig('error','code')
    refute_includes r.body,'incomplete accounting'
  end
  def test_client_and_guard_preserve_code_without_retry
    calls=0
    client=Object.new
    client.define_singleton_method(:post){|*_|calls+=1;raise SoulCore::TelemetryDiagnostic::Refused.new('helper_failed')}
    control=SoulCore::SharedComputeService.new(client:client,key_reader:-> {'a'*64})
    result=control.telemetry(handoff_id:'b'*32)
    assert_equal false,result['ok']
    assert_equal 'helper_failed',result['diagnostic_code']
    assert_equal 1,calls
    guard=SoulCore::CreativeRenderGuard.new(root:'/fixture',control:control)
    error=assert_raises(RuntimeError){guard.remote_capture(nil,'b'*32)}
    assert_equal 'coordinator telemetry unavailable: helper_failed',error.message
    assert_equal 2,calls
  end
end
