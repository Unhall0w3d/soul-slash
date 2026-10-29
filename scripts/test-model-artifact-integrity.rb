# frozen_string_literal: true
require "minitest/autorun"
require_relative "run-chat-replacement-trial"

class ModelArtifactIntegrityTest < Minitest::Test
  def setup
    @dir=Dir.mktmpdir
    @path=File.join(@dir,"model")
    @bytes="fixture\0"*150_001
    File.binwrite(@path,@bytes)
    @trial=ChatReplacementTrial.allocate
    @sha=Digest::SHA256.hexdigest(@bytes)
  end
  def teardown = FileUtils.remove_entry(@dir)
  def verify(size=@bytes.bytesize,sha=@sha) = @trial.send(:verify_file!,@path,size,sha)
  def test_full_digest_and_empty_file
    verify
    File.binwrite(@path,"")
    verify(0,Digest::SHA256.hexdigest(""))
  end
  def test_wrong_size_and_digest
    assert_raises(ChatReplacementTrial::Abort){verify(1)}
    assert_raises(ChatReplacementTrial::Abort){verify(@bytes.bytesize,"0"*64)}
  end
  def test_same_size_changed_content_is_not_cached
    verify
    File.binwrite(@path,"z"*@bytes.bytesize)
    assert_raises(ChatReplacementTrial::Abort){verify}
  end
  def test_links_rejected
    link=File.join(@dir,"link")
    File.symlink(@path,link)
    assert_raises(ChatReplacementTrial::Abort){@trial.send(:verify_file!,link,@bytes.bytesize,@sha)}
    File.unlink(link)
    File.link(@path,link)
    assert_raises(ChatReplacementTrial::Abort){verify}
  end
  def test_modification_during_hash_rejected
    with_hash_callback(-> { File.binwrite(@path,"z"*@bytes.bytesize) }) do
      assert_raises(ChatReplacementTrial::Abort){verify}
    end
  end
  def test_identical_content_path_replacement_rejected
    changed=false
    with_hash_callback(-> {
      unless changed
        File.rename(@path,"#{@path}.old")
        File.binwrite(@path,@bytes)
        changed=true
      end
    }) do
      assert_raises(ChatReplacementTrial::Abort){verify}
    end
  end
  def with_hash_callback(callback)
    digest=OpenSSL::Digest::SHA256.new
    digest.define_singleton_method(:update) do |buffer|
      callback.call
      super(buffer)
    end
    original=OpenSSL::Digest::SHA256.method(:new)
    begin
      OpenSSL::Digest::SHA256.define_singleton_method(:new){digest}
      yield
    ensure
      OpenSSL::Digest::SHA256.define_singleton_method(:new,original)
    end
  end
end
