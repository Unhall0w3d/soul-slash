# frozen_string_literal: true
module SoulCore
  # Public shell only. Media remains behind the existing authenticated routes;
  # a same-site document allows strict cookies without a bearer URL or share.
  module StudioResultReview
    VISUAL=%r{\A/(?:api/v1/visual/image|review/visual)/(visual_project_[a-f0-9]{16})/(visual_candidate_[a-f0-9]{16})\z}
    MUSIC=%r{\A/(?:api/v1/music/audio|review/music)/(music_[a-f0-9]{16})/(candidate_[a-f0-9]{16})/(mp3|flac)\z}
    def self.route(target,headers)
      if (m=VISUAL.match(target))
        kind='image';resource="/api/v1/visual/image/#{m[1]}/#{m[2]}";review="/review/visual/#{m[1]}/#{m[2]}"
      elsif (m=MUSIC.match(target))
        kind='audio';resource="/api/v1/music/audio/#{m[1]}/#{m[2]}/#{m[3]}";review="/review/music/#{m[1]}/#{m[2]}/#{m[3]}"
      else
        return
      end
      return {'redirect'=>review} if target.start_with?('/api/')&&headers['sec-fetch-mode']=='navigate'
      return unless target.start_with?('/review/')
      {'html'=>"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Soul Studio result</title><link rel=\"stylesheet\" href=\"/assets/studio-result.css\"><script defer src=\"/assets/studio-result.js\"></script></head><body><main id=\"studio-result\" data-kind=\"#{kind}\" data-resource=\"#{resource}\"><h1>Soul Studio result</h1><p>Generated draft — human review required. Nothing exported or published.</p><p id=\"result-status\" role=\"status\">Checking your dashboard session…</p><div id=\"result-media\"></div><p><a href=\"/\" id=\"dashboard-link\">Open Soul dashboard / sign in</a></p><p class=\"identity\">#{m[1]} / #{m[2]}</p></main></body></html>"}
    end
  end
end
