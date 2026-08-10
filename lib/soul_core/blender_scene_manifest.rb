#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"

module SoulCore
  # Strict closed JSON manifest parser used by Blender Scene A1.
  class BlenderSceneManifest
    class ValidationError < StandardError; end

    SCHEMA_VERSION = "soul.blender.scene_manifest.a1.v1"

    TOP_LEVEL_KEYS = %w[
      schema_version
      identity
      render
      palette
      world
      camera
      lights
      objects
      materials
      animation
      audio_binding
      look
      output
    ].freeze

    ID_KEYS = %w[id project_id revision music_candidate_id].freeze
    RENDER_KEYS = %w[renderer width height fps frame_start frame_end seed].freeze
    WORLD_KEYS = %w[horizon_color ambient_strength].freeze
    CAMERA_KEYS = %w[id type location rotation_euler lens].freeze
    LIGHT_KEYS = %w[id type location energy color].freeze
    MATERIAL_KEYS = %w[id name type base_color metallic roughness emission emission_strength].freeze
    OBJECT_KEYS = %w[id type location rotation_euler scale material].freeze
    ANIMATION_KEYS = %w[objects materials camera lights world].freeze
    AUDIO_KEYS = %w[enabled tracks].freeze
    AUDIO_TRACK_KEYS = %w[target_type target_id property curve gain offset].freeze
    OUTPUT_KEYS = %w[blend_name still_name still_frame retention].freeze
    LOOK_KEYS = %w[surface atmosphere camera glow grade].freeze

    LOOK_DEFAULTS = {
      "surface" => "clean",
      "atmosphere" => "none",
      "camera" => "crisp",
      "glow" => "none",
      "grade" => "neutral"
    }.freeze
    LOOK_SURFACES = %w[clean organic crystalline machined].freeze
    LOOK_ATMOSPHERES = %w[none mist void_haze].freeze
    LOOK_CAMERAS = %w[crisp subtle_dof cinematic_dof].freeze
    LOOK_GLOWS = %w[none soft signal].freeze
    LOOK_GRADES = %w[neutral cinematic high_contrast].freeze

    FORBIDDEN_KEYS = %w[path path_dir paths script scripts driver addon nodes import asset_path asset].freeze
    ALLOWED_RENDERERS = %w[BLENDER_EEVEE BLENDER_CYCLES].freeze
    ALLOWED_LIGHT_TYPES = %w[POINT SUN SPOT AREA].freeze
    ALLOWED_MESH_TYPES = %w[CUBE PLANE UV_SPHERE ICO_SPHERE CIRCLE CYLINDER TORUS].freeze
    ALLOWED_MATERIAL_TYPES = %w[PRINCIPLED LAMBERT SHADERLESS].freeze
    ALLOWED_ANIMATION_PROPERTIES = %w[location rotation_euler scale lens energy horizon_color emission_strength metallic roughness].freeze
    ALLOWED_WORLD_CURVES = %w[kick low_band mid_band high_band energy].freeze
    ALLOWED_TARGET_TYPES = %w[object material camera light world].freeze
    ALLOWED_OUTPUT_RETENTION = %w[preview_only full_candidate].freeze

    def initialize(manifest)
      raw = require_hash!(manifest, "manifest")
      raw = raw.dup
      raw["look"] ||= LOOK_DEFAULTS.dup
      @normalized_manifest = validate_and_normalize!(raw)
    end

    attr_reader :normalized_manifest

    def canonical_json
      JSON.generate(canonicalize(@normalized_manifest))
    end

    def sha256
      Digest::SHA256.hexdigest(canonical_json)
    end

    def to_h
      @normalized_manifest
    end

    private

    def validate_and_normalize!(manifest)
      require_exact_keys!(manifest, TOP_LEVEL_KEYS, "manifest")

      identity = validate_identity(require_hash!(manifest["identity"], "identity"))
      render = validate_render(require_hash!(manifest["render"], "render"))
      palette = validate_palette(require_hash!(manifest["palette"], "palette"))
      world = validate_world(require_hash!(manifest["world"], "world"))
      camera = validate_camera(require_hash!(manifest["camera"], "camera"))
      lights = validate_lights(require_array!(manifest["lights"], "lights"))
      materials = validate_materials(require_array!(manifest["materials"], "materials"))
      objects = validate_objects(require_array!(manifest["objects"], "objects"), materials)
      animation = validate_animation(require_hash!(manifest["animation"], "animation"), objects, materials, camera, lights, render)
      audio_binding = validate_audio_binding(require_hash!(manifest["audio_binding"], "audio_binding"), objects, materials, camera, lights)
      output = validate_output(require_hash!(manifest["output"], "output"))
      look = validate_look(require_hash!(manifest["look"], "look"))

      normalized = {
        "schema_version" => SCHEMA_VERSION,
        "identity" => identity,
        "render" => render,
        "palette" => palette,
        "world" => world,
        "camera" => camera,
        "lights" => lights,
        "objects" => objects,
        "materials" => materials,
        "animation" => animation,
        "look" => look,
        "audio_binding" => audio_binding,
        "output" => output
      }
      normalize_for_digest(normalized)
    end

    def validate_identity(identity)
      reject_unknown(identity, ID_KEYS, "identity")
      require_string!(identity["id"], "identity.id", min: 6, max: 64, pattern: /\A[a-zA-Z0-9][a-zA-Z0-9_-]{5,63}\z/)
      require_string!(identity["project_id"], "identity.project_id", min: 2, max: 48, pattern: /\A[a-zA-Z0-9][a-zA-Z0-9_-]{1,47}\z/)
      require_string!(identity["revision"], "identity.revision", min: 4, max: 32)
      require_string!(identity["music_candidate_id"], "identity.music_candidate_id", min: 4, max: 64)
      identity["id"] = identity["id"].downcase
      identity
    end

    def validate_render(render)
      reject_unknown(render, RENDER_KEYS, "render")
      require_string!(render["renderer"], "render.renderer", min: 8, max: 32)
      raise ValidationError, "renderer unsupported: #{render['renderer']}" unless ALLOWED_RENDERERS.include?(render["renderer"])
      require_int!(render["width"], "render.width", min: 64, max: 1920)
      require_int!(render["height"], "render.height", min: 64, max: 1080)
      require_int!(render["fps"], "render.fps", min: 1, max: 60)
      require_int!(render["frame_start"], "render.frame_start", min: 1, max: 10000)
      require_int!(render["frame_end"], "render.frame_end", min: 2, max: 10000)
      require_int!(render["seed"], "render.seed", min: 0, max: 2**31 - 1)
      raise ValidationError, "render.frame_end must be greater than frame_start" unless render["frame_end"] > render["frame_start"]
      render
    end

    def validate_palette(palette)
      reject_unknown(palette, %w[ambient horizon accent contrast], "palette")
      reject_forbidden(palette, "palette")
      require_color!(palette["ambient"], "palette.ambient")
      require_color!(palette["horizon"], "palette.horizon")
      require_color!(palette["accent"], "palette.accent")
      require_number!(palette["contrast"], "palette.contrast", min: 0.0, max: 3.0)
      palette
    end

    def validate_world(world)
      reject_unknown(world, WORLD_KEYS, "world")
      require_color!(world["horizon_color"], "world.horizon_color")
      require_number!(world["ambient_strength"], "world.ambient_strength", min: 0.0, max: 1.0)
      world
    end

    def validate_camera(camera)
      reject_unknown(camera, CAMERA_KEYS, "camera")
      require_string!(camera["id"], "camera.id", min: 2, max: 48, pattern: /\A[a-zA-Z0-9_-]+\z/)
      raise ValidationError, "camera.type must be PERSP" unless camera["type"] == "PERSP"
      require_vector3!(camera["location"], "camera.location")
      require_vector3!(camera["rotation_euler"], "camera.rotation_euler", min: -6.29, max: 6.29)
      require_number!(camera["lens"], "camera.lens", min: 15.0, max: 120.0)
      camera
    end

    def validate_lights(lights)
      raise ValidationError, "lights must contain at least one item" if lights.empty?
      raise ValidationError, "lights exceeds maximum of 16" if lights.length > 16
      normalized = lights.map do |light|
        light = require_hash!(light, "light")
        reject_unknown(light, LIGHT_KEYS, "light")
        reject_forbidden(light, "light")
        require_string!(light["id"], "light.id", min: 2, max: 48, pattern: /\A[a-zA-Z0-9_-]+\z/)
        raise ValidationError, "light.type unsupported" unless ALLOWED_LIGHT_TYPES.include?(light["type"])
        require_vector3!(light["location"], "light.location")
        require_number!(light["energy"], "light.energy", min: 0.1, max: 100_000.0)
        require_color!(light["color"], "light.color")
        light
      end
      require_unique_ids!(normalized, "lights")
      normalized
    end

    def validate_materials(materials)
      raise ValidationError, "materials must contain at least one item" if materials.empty?
      raise ValidationError, "materials exceeds maximum of 32" if materials.length > 32
      normalized = materials.map do |material|
        material = require_hash!(material, "material")
        reject_unknown(material, MATERIAL_KEYS, "material")
        reject_forbidden(material, "material")
        require_string!(material["id"], "material.id", min: 2, max: 64, pattern: /\A[a-zA-Z0-9_-]+\z/)
        require_string!(material["name"], "material.name", min: 1, max: 64)
        material["type"] ||= "PRINCIPLED"
        raise ValidationError, "material.type unsupported" unless ALLOWED_MATERIAL_TYPES.include?(material["type"])
        require_color!(material["base_color"], "material.base_color")
        require_number!(material["metallic"], "material.metallic", min: 0.0, max: 1.0)
        require_number!(material["roughness"], "material.roughness", min: 0.0, max: 1.0)
        if !material["emission"].nil?
          require_color!(material["emission"], "material.emission")
        end
        require_number!(material["emission_strength"], "material.emission_strength", min: 0.0, max: 10.0)
        material
      end
      require_unique_ids!(normalized, "materials")
      normalized
    end

    def validate_objects(objects, materials)
      raise ValidationError, "objects must contain at least one item" if objects.empty?
      raise ValidationError, "objects exceeds maximum of 64" if objects.length > 64
      material_ids = materials.map { |entry| entry.fetch("id") }
      normalized = objects.map do |obj|
        obj = require_hash!(obj, "object")
        reject_unknown(obj, OBJECT_KEYS, "object")
        reject_forbidden(obj, "object")
        require_string!(obj["id"], "object.id", min: 2, max: 64, pattern: /\A[a-zA-Z0-9_-]+\z/)
        raise ValidationError, "object.type unsupported" unless ALLOWED_MESH_TYPES.include?(obj["type"])
        require_vector3!(obj["location"], "object.location")
        require_vector3!(obj["rotation_euler"], "object.rotation_euler")
        require_scale_vector!(obj["scale"], "object.scale")
        raise ValidationError, "object.material unknown: #{obj['material']}" unless material_ids.include?(obj["material"])
        obj
      end
      require_unique_ids!(normalized, "objects")
      normalized
    end

    def validate_animation(animation, objects, materials, camera, lights, render)
      reject_unknown(animation, ANIMATION_KEYS, "animation")
      {
        "objects" => validate_animation_channels("animation.objects", animation["objects"], objects.map { |entry| entry["id"] }, render),
        "materials" => validate_animation_channels("animation.materials", animation["materials"], materials.map { |entry| entry["id"] }, render),
        "camera" => validate_animation_channels("animation.camera", animation["camera"], [camera["id"]], render),
        "lights" => validate_animation_channels("animation.lights", animation["lights"], lights.map { |entry| entry["id"] }, render),
        "world" => validate_animation_channels("animation.world", animation["world"], ["world"], render)
      }
    end

    def validate_animation_channels(context, channels, allowed_targets, render)
      channels = require_array!(channels, context)
      raise ValidationError, "#{context} exceeds maximum of 128 channels" if channels.length > 128
      channels.map do |channel|
        channel = require_hash!(channel, context)
        reject_unknown(channel, %w[target_id property frames values interpolation], context)
        channel["interpolation"] ||= "LINEAR"
        raise ValidationError, "animation interpolation unsupported" unless %w[LINEAR BEZIER CONSTANT].include?(channel["interpolation"])
        require_string!(channel["target_id"], "#{context}.target_id", min: 1, max: 64)
        raise ValidationError, "#{context}.target_id unknown" unless allowed_targets.include?(channel["target_id"])
        require_string!(channel["property"], "#{context}.property", min: 1, max: 64)
        raise ValidationError, "#{context}.property unsupported" unless ALLOWED_ANIMATION_PROPERTIES.include?(channel["property"])
        raise ValidationError, "#{context}.frames must be array" unless channel["frames"].is_a?(Array)
        raise ValidationError, "#{context}.values must be array" unless channel["values"].is_a?(Array)
        raise ValidationError, "#{context}.frames and values length mismatch" unless channel["frames"].length == channel["values"].length
        raise ValidationError, "#{context} channel must contain 1..512 keys" unless channel["frames"].length.between?(1, 512)
        raise ValidationError, "#{context}.frames must be strictly increasing" unless channel["frames"].each_cons(2).all? { |left, right| right > left }
        channel["frames"].each do |frame|
          require_int!(frame, "#{context}.frame", min: render["frame_start"], max: render["frame_end"])
        end
        vector_property = %w[location rotation_euler scale horizon_color].include?(channel["property"])
        channel["values"].each do |value|
          if vector_property
            raise ValidationError, "#{context}.values must be 3 values for vector properties" unless value.is_a?(Array) && value.length == 3
            vector_min, vector_max = if channel["property"] == "horizon_color"
                                      [0.0, 1.0]
                                    else
                                      [-1000.0, 1000.0]
                                    end
            value.each { |entry| require_number!(entry, "#{context}.value", min: vector_min, max: vector_max) }
          else
            raise ValidationError, "#{context}.values must be scalar for #{channel['property']}" if value.is_a?(Array)
            scalar_min, scalar_max = if channel["property"] == "lens"
                                      [1.0, 300.0]
                                    elsif channel["property"] == "energy"
                                      [0.0, 200_000.0]
                                    else
                                      [-1000.0, 1000.0]
                                    end
            require_number!(value, "#{context}.value", min: scalar_min, max: scalar_max)
          end
        end
        channel["interpolation"] = channel["interpolation"]
        channel
      end
    end

    def validate_look(look)
      reject_unknown(look, LOOK_KEYS, "look")
      reject_forbidden(look, "look")
      raise ValidationError, "look.surface invalid" unless LOOK_SURFACES.include?(look["surface"])
      raise ValidationError, "look.atmosphere invalid" unless LOOK_ATMOSPHERES.include?(look["atmosphere"])
      raise ValidationError, "look.camera invalid" unless LOOK_CAMERAS.include?(look["camera"])
      raise ValidationError, "look.glow invalid" unless LOOK_GLOWS.include?(look["glow"])
      raise ValidationError, "look.grade invalid" unless LOOK_GRADES.include?(look["grade"])
      look
    end

    def validate_audio_binding(audio_binding, objects, materials, camera, lights)
      reject_unknown(audio_binding, AUDIO_KEYS, "audio_binding")
      enabled = audio_binding["enabled"]
      raise ValidationError, "audio_binding.enabled must be boolean" unless [true, false].include?(enabled)
      tracks = require_array!(audio_binding["tracks"], "audio_binding.tracks")
      raise ValidationError, "audio_binding.tracks exceeds maximum of 32" if tracks.length > 32
      target_lookup = {
        "object" => objects.map { |entry| entry["id"] },
        "material" => materials.map { |entry| entry["id"] },
        "camera" => [camera["id"]],
        "light" => lights.map { |entry| entry["id"] },
        "world" => ["world"]
      }
      tracks = tracks.map do |track|
        track = require_hash!(track, "audio_binding.track")
        reject_unknown(track, AUDIO_TRACK_KEYS, "audio_binding.track")
        require_string!(track["target_type"], "audio_binding.track.target_type", min: 1, max: 20)
        raise ValidationError, "audio_binding track target_type unsupported" unless ALLOWED_TARGET_TYPES.include?(track["target_type"])
        raise ValidationError, "audio_binding track target_id unknown" unless target_lookup.fetch(track["target_type"]).include?(track["target_id"])
        require_string!(track["property"], "audio_binding.track.property", min: 1, max: 64)
        raise ValidationError, "audio_binding property unsupported" unless ALLOWED_ANIMATION_PROPERTIES.include?(track["property"])
        validate_target_property!(track["target_type"], track["property"], "audio_binding.track")
        require_string!(track["curve"], "audio_binding.track.curve", min: 3, max: 20)
        raise ValidationError, "audio_binding track curve unsupported" unless ALLOWED_WORLD_CURVES.include?(track["curve"])
        require_number!(track["gain"], "audio_binding.track.gain", min: 0.0, max: 5.0)
        require_int!(track["offset"], "audio_binding.track.offset", min: 0, max: 5000)
        track["gain"] = track["gain"].to_f
        track
      end
      {
        "enabled" => enabled,
        "tracks" => tracks
      }
    end

    def validate_output(output)
      reject_unknown(output, OUTPUT_KEYS, "output")
      require_file_name!(output["blend_name"], "output.blend_name")
      require_file_name!(output["still_name"], "output.still_name")
      require_int!(output["still_frame"], "output.still_frame", min: 1, max: 10_000)
      raise ValidationError, "output.retention unsupported" unless ALLOWED_OUTPUT_RETENTION.include?(output["retention"])
      output
    end

    def require_unique_ids!(entries, context)
      ids = entries.map { |entry| entry.fetch("id") }
      duplicates = ids.group_by(&:itself).select { |_id, values| values.length > 1 }.keys
      raise ValidationError, "#{context} contains duplicate ids: #{duplicates.join(', ')}" unless duplicates.empty?
    end

    def validate_target_property!(target_type, property, context)
      allowed = {
        "object" => %w[location rotation_euler scale],
        "material" => %w[emission_strength metallic roughness],
        "camera" => %w[location rotation_euler lens],
        "light" => %w[location rotation_euler energy],
        "world" => %w[horizon_color]
      }.fetch(target_type)
      raise ValidationError, "#{context} property #{property} is invalid for #{target_type}" unless allowed.include?(property)
    end

    def require_exact(data, context)
      raise ValidationError, "#{context} must be a hash" unless data.is_a?(Hash)
      data
    end

    def reject_unknown(data, allowed, context)
      data = require_exact(data, context)
      extras = data.keys - allowed
      raise ValidationError, "#{context} has unknown keys: #{extras.join(", ")}" unless extras.empty?
      required = allowed - %w[offset]
      missing = required - data.keys
      raise ValidationError, "#{context} missing keys: #{missing.join(", ")}" unless missing.empty?
      data
    end

    def reject_forbidden(data, context)
      forbidden = data.keys & FORBIDDEN_KEYS
      raise ValidationError, "#{context} uses forbidden key: #{forbidden.join(", ")}" unless forbidden.empty?
    end

    def require_hash!(value, context)
      raise ValidationError, "#{context} must be a map" unless value.is_a?(Hash)
      value
    end

    def require_array!(value, context)
      raise ValidationError, "#{context} must be an array" unless value.is_a?(Array)
      value
    end

    def require_exact_keys!(data, required_keys, context)
      data = require_hash!(data, context)
      missing = required_keys - data.keys
      extras = data.keys - required_keys
      raise ValidationError, "#{context} missing keys: #{missing.join(", ")}" unless missing.empty?
      raise ValidationError, "#{context} has unknown keys: #{extras.join(", ")}" unless extras.empty?
      data
    end

    def require_string!(value, label, min:, max:, pattern: nil)
      unless value.is_a?(String) && value.length.between?(min, max)
        raise ValidationError, "#{label} must be a string with #{min}-#{max} chars"
      end
      raise ValidationError, "#{label} contains forbidden or unsupported pattern" if pattern && value !~ pattern
      value
    end

    def require_number!(value, label, min:, max:)
      raise ValidationError, "#{label} must be numeric" unless value.is_a?(Numeric)
      number = value.to_f
      raise ValidationError, "#{label} must be between #{min} and #{max}" unless number.between?(min, max)
      number
    end

    def require_int!(value, label, min:, max:)
      unless value.is_a?(Integer)
        raise ValidationError, "#{label} must be integer"
      end
      raise ValidationError, "#{label} must be between #{min} and #{max}" unless value.between?(min, max)
      value
    end

    def require_color!(value, label)
      require_vector3!(value, label)
      value.each do |channel|
        require_number!(channel, label, min: 0.0, max: 1.0)
      end
    end

    def require_vector3!(value, label, min: -1000.0, max: 1000.0)
      raise ValidationError, "#{label} must be 3-number vector" unless value.is_a?(Array) && value.length == 3
      value.each { |entry| require_number!(entry, label, min: min, max: max) }
      value
    end

    def require_scale_vector!(value, label)
      raise ValidationError, "#{label} must be 3-number vector" unless value.is_a?(Array) && value.length == 3
      value.each { |entry| require_number!(entry, label, min: 0.05, max: 25.0) }
      value
    end

    def require_file_name!(value, label)
      raise ValidationError, "#{label} must be a string" unless value.is_a?(String)
      raise ValidationError, "#{label} must be file name only" if value.include?("/") || value.include?("\\")
      raise ValidationError, "#{label} invalid name" unless value =~ /\A[a-zA-Z0-9._-]+\z/
      if label.include?("blend")
        raise ValidationError, "#{label} must end in .blend" unless value.end_with?(".blend")
      elsif label.include?("still")
        raise ValidationError, "#{label} must end in .png" unless value.end_with?(".png")
      end
      raise ValidationError, "#{label} cannot be empty" if value.empty?
      value
    end

    def normalize_for_digest(manifest)
      normalized = JSON.parse(JSON.generate(manifest))
      normalized["lights"] = manifest.fetch("lights").sort_by { |entry| entry.fetch("id") }
      normalized["materials"] = manifest.fetch("materials").sort_by { |entry| entry.fetch("id") }
      normalized["objects"] = manifest.fetch("objects").sort_by { |entry| entry.fetch("id") }
      normalized["animation"] = {}
      ANIMATION_KEYS.each do |section|
        normalized["animation"][section] = manifest.fetch("animation").fetch(section).sort_by do |entry|
          [entry.fetch("target_id"), entry.fetch("property"), entry.fetch("frames").first.to_i]
        end
      end
      normalized["audio_binding"] = {
        "enabled" => manifest.fetch("audio_binding").fetch("enabled"),
        "tracks" => manifest.fetch("audio_binding").fetch("tracks").sort_by { |entry| [entry.fetch("target_type"), entry.fetch("target_id"), entry.fetch("property")] }
      }
      normalized["identity"] = manifest.fetch("identity")
      normalized["camera"] = manifest.fetch("camera").sort_by { |key, _| key }.to_h
      normalized["world"] = manifest.fetch("world").sort_by { |key, _| key }.to_h
      normalized["output"] = manifest.fetch("output").sort_by { |key, _| key }.to_h
      normalized["palette"] = manifest.fetch("palette").sort_by { |key, _| key }.to_h
      normalized["render"] = manifest.fetch("render").sort_by { |key, _| key }.to_h
      normalized["look"] = manifest.fetch("look").sort_by { |key, _| key }.to_h
      normalized
    end

    def canonicalize(value)
      case value
      when Hash
        sorted = value.keys.sort.each_with_object({}) do |key, result|
          result[key] = canonicalize(value.fetch(key))
        end
        sorted
      when Array
        value.map { |entry| canonicalize(entry) }
      when Float
        # Keep predictable JSON number representation for canonical hash.
        value.to_s.include?(".") ? value : value.to_f
      else
        value
      end
    end
  end
end
