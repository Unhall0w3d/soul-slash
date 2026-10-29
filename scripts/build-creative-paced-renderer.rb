#!/usr/bin/env ruby
# Build an isolated executable from the installed runtime's exact static objects.
# No installed source, model, manifest, binary or build directory is modified.
require 'json'
require 'digest'
require 'tmpdir'
require 'open3'
require 'time'
require_relative '../lib/soul_core/bounded_command_runner'
abort 'Usage: build-creative-paced-renderer.rb SOURCE_ROOT' unless ARGV.size == 1
source = File.realpath(ARGV.fetch(0))
root = File.expand_path('..', __dir__)
build = File.join(source, 'build')
expected = '6aeb8f028f70db3d22dbe1844a87634d4341c427d5258dfd5aa498b18e8bb496'
%w[bin/sd-cli build/bin/sd-cli].each do |relative|
  abort 'Installed runtime drift' unless Digest::SHA256.file(File.join(source,relative)).hexdigest == expected
end
File.umask(0077)
out = Dir.mktmpdir('paced-renderer-build-', File.join(root,'Soul/runtime/qualification'))
receipt = {state: 'building', started_at: Time.now.utc.iso8601, baseline_sha256: expected, output: out, commands: []}
runner = SoulCore::BoundedCommandRunner.new
begin
  objects = %w[thirdparty/CMakeFiles/zip.dir/zip.c.o examples/cli/CMakeFiles/sd-cli.dir/__/common/common.cpp.o examples/cli/CMakeFiles/sd-cli.dir/__/common/log.cpp.o examples/cli/CMakeFiles/sd-cli.dir/__/common/media_io.cpp.o examples/cli/CMakeFiles/sd-cli.dir/image_metadata.cpp.o examples/cli/CMakeFiles/sd-cli.dir/main.cpp.o]
  libraries = %w[libstable-diffusion.a thirdparty/libwebp/libwebp.a thirdparty/libwebp/libwebpmux.a thirdparty/libwebm/libwebm.a ggml/src/libggml.a -ldl ggml/src/libggml-cpu.a ggml/src/ggml-vulkan/libggml-vulkan.a ggml/src/libggml-base.a /usr/lib/libgomp.so /usr/lib/libpthread.a /usr/lib/libvulkan.so thirdparty/libwebp/libwebp.a thirdparty/libwebp/libsharpyuv.a -lm]
  inputs = (objects + libraries).map { |s| s.start_with?('-') ? s : File.expand_path(s,build) }
  support = File.join(__dir__,'support/creative_thermal_pacer.cpp')
  hashes = (inputs.reject{|s|s.start_with?('-')} + [support, support.sub('.cpp','.h')]).uniq.to_h{|p|[p,Digest::SHA256.file(p).hexdigest]}
  receipt[:inputs_sha256] = hashes
  binary = File.join(out,'sd-cli')
  commands = [
    ['/usr/bin/c++','-std=c++17','-O2','-Wall','-Wextra','-Werror','-c',support,'-o',File.join(out,'pacer.o')],
    ['/usr/bin/c++','-O3','-DNDEBUG',*inputs.first(objects.size),File.join(out,'pacer.o'),'-o',binary,'-Wl,--wrap=_Z15pretty_progressiif',*inputs.drop(objects.size)]
  ]
  commands.each do |command|
    r = runner.run(*command,timeout_seconds:120,max_output_bytes:65536)
    receipt[:commands] << {argv:command,status:r.status,stderr:r.stderr}
    raise 'build failed' unless r.success?
  end
  raise 'build input changed' unless hashes.all?{|p,h|Digest::SHA256.file(p).hexdigest==h}
  raise 'baseline changed' unless Digest::SHA256.file(File.join(source,'bin/sd-cli')).hexdigest==expected
  r = runner.run(binary,'--version',timeout_seconds:10)
  raise 'version smoke failed' unless r.success?
  receipt.merge!(state:'built_not_live_qualified',binary:binary,sha256:Digest::SHA256.file(binary).hexdigest,version:r.stdout)
rescue StandardError => e
  receipt.merge!(state:'failed',error:"#{e.class}: #{e.message}")
ensure
  receipt[:finished_at]=Time.now.utc.iso8601
  File.write(File.join(out,'receipt.json'),JSON.pretty_generate(receipt),mode:'wx',perm:0600)
  puts JSON.generate(receipt.slice(:state,:output,:binary,:sha256,:error))
end
exit(receipt[:state]=='built_not_live_qualified' ? 0 : 1)
