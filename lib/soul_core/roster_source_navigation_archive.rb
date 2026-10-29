# frozen_string_literal: true
require_relative 'roster_archive_gateway'
require_relative 'roster_source_navigation_gateway'
require_relative 'roster_navigation_archive'
require_relative 'roster_read_only_archive'
module SoulCore
  # Versioned archive. Existing archive implementations and bindings stay intact.
  class RosterSourceNavigationArchive < RosterArchiveGateway
    def self.read_only_skills? = true
    def self.manifest(owner)
      super.merge('version'=>'roster_source_navigation_archive_v1',
        'conversation_binding'=>RosterSourceNavigationGateway.manifest(owner),
        'implementation_sha256'=>Digest::SHA256.file(__FILE__).hexdigest,
        'archive_base_sha256'=>Digest::SHA256.file(File.join(__dir__,'roster_archive_gateway.rb')).hexdigest)
    end
    def self.transition(source:,path:,owner:,expected_manifest_sha256:)
      old=RosterNavigationArchive.new(path:source,owner:owner)
      raise Refused,'source busy' unless old.instance_variable_get(:@lock).flock(File::LOCK_EX|File::LOCK_NB)
      manifest=old.instance_variable_get(:@manifest)
      raise Refused,'source binding changed' unless digest(manifest)==expected_manifest_sha256
      count=0;request_ids=[]
      publish(path:path,owner:owner) do |store|
        old.instance_variable_get(:@conversations).children.sort.each do |name|
          envelope=Directory.new(File.join(source,'conversations',name))
          id=envelope.read('descriptor.json').fetch('conversation_id');envelope.close
          raise Refused,'source identity mismatch' unless digest(id)==name
          inner=old.send(:open_conversation,id)
          begin
            inner.send(:load!)
            attempts=inner.instance_variable_get(:@attempts)
            raise Refused,'unfinished source' unless attempts.values.all?{|v|%w[complete failed canceled].include?(v['state'])}
            attempts.each_value do |attempt|
              input=attempt.fetch('input')
              raise Refused,'source reservation changed' unless old.send(:registration_for,input['request_id'])&.slice('request_id','conversation_id','input_sha256')==old.send(:reservation,input)
            end
            records=inner.instance_variable_get(:@records).reject{|r|%w[transition implementation_transition].include?(r['state'])}
            store.send(:create_conversation!,id,subset:records,source_manifest:inner.instance_variable_get(:@manifest))
            attempts.each_value{|attempt|store.send(:reserve!,attempt.fetch('input'))}
            count+=attempts.length;request_ids.concat(attempts.keys)
          ensure
            inner.close
          end
        end
        registry_ids=[]
        old.instance_variable_get(:@requests).children.each do |bucket|
          directory=Directory.new(File.join(source,'requests',bucket))
          begin
            directory.children.each do |name|
              id=directory.read(name,4096).fetch('request_id')
              raise Refused,'source reservation incomplete' unless old.send(:registration_for,id)
              registry_ids<<id
            end
          ensure
            directory.close
          end
        end
        raise Refused,'orphan source registry entry' unless registry_ids.sort==request_ids.sort
        raise Refused,'orphan source request reservation' unless old.instance_variable_get(:@keys).children.sort==request_ids.map{|id|digest(id)+'.json'}.sort
        nil
      end
      {'state'=>'complete','requests'=>count,'source_manifest_sha256'=>expected_manifest_sha256,'source_preserved'=>true}
    ensure
      old&.close
    end
    private
    def create_conversation!(id, subset: [], source_manifest: nil)
      @conversations.verify!
      name=self.class.digest(id)
      raise Refused,"conversation already exists" if exists?(@conversations, name)
      stage="stage-#{SecureRandom.hex(16)}"
      Dir.mkdir(@conversations.anchor(stage),0o700)
      path=File.join(@conversations.path,stage); envelope=Directory.new(path)
      RosterSourceNavigationGateway.create(path:File.join(path,"journal"),owner:@owner)
      inner=RosterSourceNavigationGateway.new(path:File.join(path,"journal"),owner:@owner,memory:@memory,clock:@clock)
      inner.send(:load!)
      unless subset.empty?
        inner.send(:append!,"source_navigation_import","archive-import",{"skill_lineages"=>subset.select{|r|r["state"]=="skill_complete"}.to_h{|r|[r["request_id"],r.dig("data","lineage")]},"source_manifest_sha256"=>self.class.digest(source_manifest),
          "source_tail_sha256"=>self.class.digest(subset.last),"imported_records"=>subset.length,
          "payloads_sha256"=>self.class.digest(subset.map { |r| r.values_at("state","request_id","data") })})
        subset.each { |r| inner.send(:append!,r["state"],r["request_id"],r["data"]) }
        inner.send(:load!)
      end
      descriptor={"conversation_id"=>id,"journal_manifest_sha256"=>self.class.digest(inner.instance_variable_get(:@manifest))}
      envelope.write("descriptor.json",descriptor)
      inner.close;inner=nil;envelope.verify!;@conversations.verify!
      raise Refused,"conversation destination appeared" if exists?(@conversations, name)
      File.rename(@conversations.anchor(stage),@conversations.anchor(name));@conversations.sync
    ensure
      inner&.close;envelope&.close
    end

    def open_conversation(id)
      envelope=Directory.new(File.join(@conversations.path,self.class.digest(id)))
      raise Refused,"conversation envelope changed" unless envelope.children.sort==%w[descriptor.json journal]
      descriptor=envelope.read("descriptor.json")
      raise Refused,"conversation identity changed" unless descriptor.keys.sort==%w[conversation_id journal_manifest_sha256] && descriptor["conversation_id"]==id
      inner=RosterSourceNavigationGateway.new(path:File.join(envelope.path,"journal"),owner:@owner,memory:@memory,clock:@clock)
      raise Refused,"conversation journal replaced" unless self.class.digest(inner.instance_variable_get(:@manifest))==descriptor["journal_manifest_sha256"]
      inner
    rescue Exception
      inner&.close
      raise
    ensure
      envelope&.close
    end

  end
end
