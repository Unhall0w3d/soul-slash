# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/soul_core/dashboard_http_application'
class StudioResultReviewTest < Minitest::Test
  def test_typed_navigation_redirect_does_not_disclose_media
    path='/api/v1/visual/image/visual_project_0123456789abcdef/visual_candidate_fedcba9876543210'
    r=SoulCore::StudioResultReview.route(path,{'sec-fetch-mode'=>'navigate'})
    assert_equal '/review/visual/visual_project_0123456789abcdef/visual_candidate_fedcba9876543210',r['redirect']
    assert_nil SoulCore::StudioResultReview.route(path,{})
    assert_nil SoulCore::StudioResultReview.route('/review/visual/../../secret',{})
    assert_nil SoulCore::StudioResultReview.route(path+'?token=secret',{})
    html=SoulCore::StudioResultReview.route(r['redirect'],{})['html'];assert_includes html,'human review required';refute_includes html,'Bearer';refute_includes html,'<img'
  end
  def test_audio_shell_and_existing_api_authentication_are_separate
    root=Dir.mktmpdir
    facade=Object.new;def facade.music_artifact_path(**) = raise('unauthenticated media must not be read')
    auth=Object.new;def auth.session(*) = nil
    app=SoulCore::DashboardHttpApplication.new(root:root,facade:facade,bind_host:'127.0.0.1',port:4567,authentication:auth)
    api='/api/v1/music/audio/music_0123456789abcdef/candidate_fedcba9876543210/mp3'
    response=app.call(method:'GET',target:api,headers:{'host'=>'127.0.0.1:4567'})
    assert_equal 401,response.status
    nav=app.call(method:'GET',target:api,headers:{'host'=>'127.0.0.1:4567','sec-fetch-mode'=>'navigate'})
    assert_equal 303,nav.status
    shell=app.call(method:'GET',target:nav.headers['Location'],headers:{'host'=>'127.0.0.1:4567'})
    assert_equal 200,shell.status;assert_includes shell.body,'data-kind="audio"';assert_includes shell.headers['Content-Security-Policy'],"media-src 'self' blob:"
  ensure
    FileUtils.remove_entry(root) if root
  end
end
