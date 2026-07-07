#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"

archive_dir = "docs/overlays/archive"
FileUtils.mkdir_p(archive_dir)

moved = []

Dir.glob("README_*.md").sort.each do |source|
  next unless File.file?(source)

  target = File.join(archive_dir, File.basename(source))

  if File.exist?(target)
    base = File.basename(source, ".md")
    target = File.join(archive_dir, "#{base}-archived.md")
  end

  FileUtils.mv(source, target)
  moved << [source, target]
end

puts "Archived root overlay README files:"
if moved.empty?
  puts "- none found"
else
  moved.each { |source, target| puts "- #{source} -> #{target}" }
end

gitignore = ".gitignore"
if File.exist?(gitignore)
  text = File.read(gitignore)
  block = <<~GITIGNORE

    # Root overlay instruction files should be archived under docs/overlays/archive/.
    /README_*.md
  GITIGNORE

  unless text.include?("/README_*.md")
    File.write(gitignore, text.rstrip + "\n" + block)
    puts "Patched .gitignore: added /README_*.md"
  else
    puts ".gitignore already ignores /README_*.md"
  end
end
