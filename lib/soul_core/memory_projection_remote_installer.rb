# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "shellwords"
require "tmpdir"
require "time"
require_relative "memory_projection_deployment_plan"

module SoulCore
  class MemoryProjectionRemoteInstaller
    SCHEMA = "soul.memory_projection_remote_installer.a20.v1"
    CONFIRM_INSTALL = MemoryProjectionDeploymentPlan::CONFIRM_INSTALL
    CONFIRM_REMOVE = "REMOVE_SOUL_MEMORY_PROJECTION"
    MAX_PRIVATE_FILE = 128 * 1024

    def initialize(root:, manifest_path:, private_config_path:, runner: nil)
      @root = File.expand_path(root)
      @manifest_path = File.expand_path(manifest_path)
      @private_config_path = File.expand_path(private_config_path)
      @runner = runner || method(:capture)
    end

    def plan
      config = private_config
      evidence = fresh_evidence(config)
      parameters = deployment_parameters(config)
      planned = MemoryProjectionDeploymentPlan.new(manifest_path: @manifest_path).plan(parameters)
      return planned unless planned.dig("data", "expected_digest")

      scope = planned.fetch("data").merge(
        "preflight_evidence_sha256" => Digest::SHA256.hexdigest(File.binread(config.fetch("preflight_evidence_path"))),
        "preflight_observed_at" => evidence.fetch("observed_at"),
        "template" => config.fetch("template"),
        "nameserver" => config.fetch("nameserver"),
        "installer_schema" => SCHEMA
      )
      scope.delete("expected_digest")
      scope.delete("confirmation_phrase")
      scope.delete("mutation")
      outcome(false, "blocked_for_human_review", "Review the exact fresh memory projection deployment plan.",
        scope.merge("confirmation_phrase" => CONFIRM_INSTALL, "expected_digest" => digest(scope)))
    rescue StandardError => error
      outcome(false, "failed", "Memory projection deployment plan failed safely: #{error.class}: #{error.message}", {})
    end

    def install(confirmation:, expected_digest:)
      planned = plan
      return planned if planned["lifecycle_state"] == "failed"
      data = planned.fetch("data")
      unless confirmation == CONFIRM_INSTALL && secure_compare(expected_digest, data.fetch("expected_digest"))
        return outcome(false, "blocked_for_human_review", "Memory projection deployment confirmation or digest is stale.", data)
      end

      config = private_config
      bundle = build_bundle(config)
      vmid = Integer(config.fetch("vmid"))
      remote_stage = "/root/soul-memory-projection-#{vmid}"
      commands = install_commands(config, bundle, remote_stage)
      commands.each_with_index do |command, index|
        execution = @runner.call(command)
        unless execution.fetch("success")
          return outcome(false, "failed", "Memory projection deployment stopped at fixed phase #{index + 1}.",
            {"phase" => data.fetch("phases").fetch([index, data.fetch("phases").length - 1].min), "stderr" => bounded(execution["stderr"])}, "remote_deployment_partial")
        end
      end
      outcome(true, "complete", "Memory projection services were installed and verified.",
        {"target" => data.fetch("target"), "expected_digest" => data.fetch("expected_digest"), "services" => ["qdrant", "redis-server"]}, "remote_deployment")
    ensure
      FileUtils.remove_entry_secure(bundle) if defined?(bundle) && bundle && Dir.exist?(bundle)
    end

    def remove(confirmation:)
      config = private_config
      return outcome(false, "awaiting_input", "Exact removal confirmation is required.", {"confirmation_phrase" => CONFIRM_REMOVE}) unless confirmation == CONFIRM_REMOVE
      vmid = Integer(config.fetch("vmid"))
      command = ssh(config, "pct stop #{vmid} --skiplock 1 >/dev/null 2>&1 || true; pct destroy #{vmid} --purge 1")
      execution = @runner.call(command)
      return outcome(false, "failed", "Exact projection guest removal failed safely.", {"stderr" => bounded(execution["stderr"])}) unless execution.fetch("success")
      outcome(true, "complete", "Exact owned projection guest removed; canonical memory was unchanged.", {"vmid" => vmid}, "remote_guest_removal")
    end

    def repair
      config = private_config
      vmid = Integer(config.fetch("vmid"))
      directory = Dir.mktmpdir("soul-memory-projection-repair-")
      File.chmod(0o700, directory)
      script = File.join(directory, "repair.sh")
      File.write(script, repair_script, mode: "wb", perm: 0o700)
      remote = "/root/soul-memory-projection-repair-#{vmid}"
      commands = [
        ["scp", "-q", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", script, "#{config.fetch("target_alias")}:#{remote}"],
        ssh(config, "pct push #{vmid} #{remote} /root/repair.sh --perms 700 && pct exec #{vmid} -- /root/repair.sh && rm -f #{remote}")
      ]
      commands.each do |command|
        execution = @runner.call(command)
        return outcome(false, "failed", "Memory projection compatibility repair failed safely.", {"stderr" => bounded(execution["stderr"])}, "remote_repair_partial") unless execution.fetch("success")
      end
      outcome(true, "complete", "Memory projection compatibility repair completed.", {"vmid" => vmid}, "remote_repair")
    ensure
      FileUtils.remove_entry_secure(directory) if defined?(directory) && directory && Dir.exist?(directory)
    end

    private

    def private_config
      raise "private configuration is unavailable" unless private_file?(@private_config_path, MAX_PRIVATE_FILE)
      value = JSON.parse(File.binread(@private_config_path))
      raise "private configuration schema mismatch" unless value["schema_version"] == "soul.memory-projection.private.a20.v1"
      value
    rescue JSON::ParserError
      raise "private configuration JSON is malformed"
    end

    def fresh_evidence(config)
      path = File.expand_path(config.fetch("preflight_evidence_path"))
      raise "preflight evidence is not owner-private" unless private_file?(path, MAX_PRIVATE_FILE)
      evidence = JSON.parse(File.binread(path))
      raise "preflight evidence schema mismatch" unless evidence["schema_version"] == "soul.memory-projection.preflight.a20.v1"
      age = Time.now.to_i - Time.iso8601(evidence.fetch("observed_at")).to_i
      raise "preflight evidence is stale" unless age.between?(0, 600)
      raise "target hypervisor mismatch" unless evidence["target_alias"] == config["target_alias"]
      raise "guest VMID is no longer free" unless evidence["vmid_free"] == true
      raise "guest address is no longer free" unless evidence["address_free"] == true
      raise "insufficient available memory" unless Integer(evidence["available_memory_bytes"]) >= 3 * 1024 * 1024 * 1024
      raise "insufficient available storage" unless Integer(evidence["available_storage_bytes"]) >= 30 * 1024 * 1024 * 1024
      evidence
    rescue JSON::ParserError, ArgumentError
      raise "preflight evidence is malformed"
    end

    def deployment_parameters(config)
      result = config.slice("target_alias", "vmid", "fqdn", "ipv4", "gateway", "client_ipv4")
      {
        "client_ca_sha256" => file_digest(config, "ca_certificate_path"),
        "server_certificate_sha256" => file_digest(config, "server_certificate_path"),
        "qdrant_api_key_sha256" => file_digest(config, "qdrant_api_key_path"),
        "falkordb_password_sha256" => file_digest(config, "falkordb_password_path"),
        "ssh_public_key_sha256" => file_digest(config, "ssh_public_key_path")
      }.merge(result)
    end

    def file_digest(config, key)
      path = File.expand_path(config.fetch(key))
      raise "#{key} is not owner-private" unless private_file?(path, MAX_PRIVATE_FILE)
      Digest::SHA256.hexdigest(File.binread(path))
    end

    def private_file?(path, ceiling)
      File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, ceiling) && (File.stat(path).mode & 0o077).zero?
    end

    def build_bundle(config)
      directory = Dir.mktmpdir("soul-memory-projection-")
      File.chmod(0o700, directory)
      copies = {
        "qdrant.deb" => config.fetch("qdrant_artifact_path"),
        "falkordb-x64.so" => config.fetch("falkordb_artifact_path"),
        "ca.crt" => config.fetch("ca_certificate_path"),
        "server.crt" => config.fetch("server_certificate_path"),
        "server.key" => config.fetch("server_key_path"),
        "authorized_keys" => config.fetch("ssh_public_key_path"),
        "qdrant-api-key" => config.fetch("qdrant_api_key_path"),
        "falkordb-password" => config.fetch("falkordb_password_path")
      }
      copies.each do |name, source|
        source = File.expand_path(source)
        raise "deployment input #{name} is unsafe" unless private_file?(source, 128 * 1024 * 1024)
        FileUtils.cp(source, File.join(directory, name), preserve: false)
        File.chmod(0o600, File.join(directory, name))
      end
      File.write(File.join(directory, "install.sh"), install_script(config), mode: "wb", perm: 0o700)
      directory
    end

    def install_commands(config, bundle, remote_stage)
      vmid = Integer(config.fetch("vmid"))
      net = "name=eth0,bridge=vmbr0,ip=#{config.fetch("ipv4")}/24,gw=#{config.fetch("gateway")},type=veth"
      create = ["pct create", vmid, Shellwords.escape(config.fetch("template")), "--hostname", Shellwords.escape(config.fetch("guest_hostname")),
        "--cores 2 --memory 2048 --swap 512 --rootfs local-lvm:24 --unprivileged 1 --onboot 1",
        "--features nesting=0", "--nameserver", Shellwords.escape(config.fetch("nameserver")), "--searchdomain herz.soul",
        "--net0", Shellwords.escape(net)].join(" ")
      [
        ssh(config, "test ! -e /etc/pve/lxc/#{vmid}.conf && #{create} && pct start #{vmid}"),
        ["scp", "-q", "-r", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", bundle, "#{config.fetch("target_alias")}:#{remote_stage}"],
        ssh(config, "pct push #{vmid} #{remote_stage}/install.sh /root/install.sh --perms 700 && for f in qdrant.deb falkordb-x64.so ca.crt server.crt server.key authorized_keys qdrant-api-key falkordb-password; do pct push #{vmid} #{remote_stage}/$f /root/$f --perms 600; done && pct exec #{vmid} -- /root/install.sh && rm -rf #{remote_stage}"),
        ssh(config, "pct exec #{vmid} -- systemctl is-active --quiet qdrant redis-server ssh nftables && pct exec #{vmid} -- /usr/bin/curl --fail --silent --cacert /etc/soul-memory/ca.crt -H \"api-key: $(pct exec #{vmid} -- cat /etc/soul-memory/qdrant-api-key)\" https://#{config.fetch("fqdn")}:6333/collections >/dev/null && pct exec #{vmid} -- /usr/bin/redis-cli --tls --cacert /etc/soul-memory/ca.crt -h #{config.fetch("fqdn")} -p 6379 -a \"$(pct exec #{vmid} -- cat /etc/soul-memory/falkordb-password)\" PING | grep -qx PONG")
      ]
    end

    def install_script(config)
      <<~SH
        #!/bin/sh
        set -eu
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y --no-install-recommends redis-server nftables openssh-server curl ca-certificates libgomp1
        dpkg -i /root/qdrant.deb
        install -d -m 0750 /etc/soul-memory /etc/qdrant /var/lib/qdrant/storage /var/lib/qdrant/snapshots /usr/lib/falkordb
        install -m 0644 /root/ca.crt /etc/soul-memory/ca.crt
        install -m 0644 /root/server.crt /etc/soul-memory/server.crt
        install -m 0600 /root/server.key /etc/soul-memory/server.key
        install -m 0600 /root/qdrant-api-key /etc/soul-memory/qdrant-api-key
        install -m 0600 /root/falkordb-password /etc/soul-memory/falkordb-password
        install -m 0755 /root/falkordb-x64.so /usr/lib/falkordb/falkordb-x64.so
        chown root:redis /usr/lib/falkordb
        chmod 0750 /usr/lib/falkordb
        id souladmin >/dev/null 2>&1 || useradd --create-home --shell /bin/bash souladmin
        install -d -m 0700 -o souladmin -g souladmin /home/souladmin/.ssh
        install -m 0600 -o souladmin -g souladmin /root/authorized_keys /home/souladmin/.ssh/authorized_keys
        id qdrant >/dev/null 2>&1 || useradd --system --home /var/lib/qdrant --shell /usr/sbin/nologin qdrant
        chown -R qdrant:qdrant /var/lib/qdrant
        getent group soul-memory-tls >/dev/null || groupadd --system soul-memory-tls
        usermod -aG soul-memory-tls qdrant
        usermod -aG soul-memory-tls redis
        chown root:soul-memory-tls /etc/soul-memory
        chmod 0750 /etc/soul-memory
        chown root:soul-memory-tls /etc/soul-memory/server.key
        chown root:qdrant /etc/soul-memory/qdrant-api-key
        chmod 0640 /etc/soul-memory/server.key /etc/soul-memory/qdrant-api-key
        QKEY=$(cat /etc/soul-memory/qdrant-api-key)
        FPASS=$(cat /etc/soul-memory/falkordb-password)
        cat > /etc/qdrant/config.yaml <<EOF
        storage:
          storage_path: /var/lib/qdrant/storage
          snapshots_path: /var/lib/qdrant/snapshots
        service:
          host: 0.0.0.0
          http_port: 6333
          grpc_port: null
          enable_cors: false
          enable_tls: true
          api_key: $QKEY
        telemetry_disabled: true
        tls:
          cert: /etc/soul-memory/server.crt
          key: /etc/soul-memory/server.key
          ca_cert: /etc/soul-memory/ca.crt
        EOF
        chown root:qdrant /etc/qdrant/config.yaml
        chown root:qdrant /etc/qdrant
        chmod 0750 /etc/qdrant
        chmod 0640 /etc/qdrant/config.yaml
        cat > /etc/systemd/system/qdrant.service <<'EOF'
        [Unit]
        Description=Qdrant vector projection
        After=network-online.target
        Wants=network-online.target
        [Service]
        User=qdrant
        Group=qdrant
        ExecStart=/usr/bin/qdrant --config-path /etc/qdrant/config.yaml
        Restart=on-failure
        RestartSec=5s
        MemoryMax=768M
        NoNewPrivileges=true
        PrivateTmp=true
        ProtectSystem=strict
        ProtectHome=true
        ReadWritePaths=/var/lib/qdrant
        [Install]
        WantedBy=multi-user.target
        EOF
        cat > /etc/redis/redis.conf <<EOF
        bind 0.0.0.0
        protected-mode yes
        port 0
        tls-port 6379
        tls-cert-file /etc/soul-memory/server.crt
        tls-key-file /etc/soul-memory/server.key
        tls-ca-cert-file /etc/soul-memory/ca.crt
        tls-auth-clients no
        requirepass $FPASS
        appendonly yes
        appendfsync everysec
        maxmemory 512mb
        maxmemory-policy noeviction
        loadmodule /usr/lib/falkordb/falkordb-x64.so
        supervised systemd
        dir /var/lib/redis
        logfile /var/log/redis/redis-server.log
        EOF
        chown root:soul-memory-tls /etc/soul-memory/server.key
        chown redis:redis /etc/soul-memory/falkordb-password
        chmod 0640 /etc/soul-memory/server.key /etc/soul-memory/falkordb-password
        touch /var/log/redis/redis-server.log
        chown redis:adm /var/log/redis/redis-server.log
        chmod 0640 /var/log/redis/redis-server.log
        chown root:redis /usr/lib/falkordb
        chmod 0750 /usr/lib/falkordb
        install -d -m 0755 /etc/systemd/system/redis-server.service.d
        cat > /etc/systemd/system/redis-server.service.d/60-lxc-compat.conf <<'EOF'
        [Service]
        PrivateUsers=false
        EOF
        systemctl set-property redis-server.service MemoryMax=768M
        cat > /etc/nftables.conf <<'EOF'
        flush ruleset
        table inet filter {
          chain input {
            type filter hook input priority 0; policy drop;
            iif lo accept
            ct state established,related accept
            ip protocol icmp accept
            ip saddr #{config.fetch("client_ipv4")} tcp dport { 22, 6333, 6379 } accept
          }
          chain forward { type filter hook forward priority 0; policy drop; }
          chain output { type filter hook output priority 0; policy accept; }
        }
        EOF
        rm -f /root/qdrant.deb /root/falkordb-x64.so /root/ca.crt /root/server.crt /root/server.key /root/authorized_keys /root/qdrant-api-key /root/falkordb-password
        systemctl daemon-reload
        systemctl enable ssh nftables qdrant redis-server
        systemctl restart nftables ssh qdrant redis-server
      SH
    end


    def repair_script
      <<~SH
        #!/bin/sh
        set -eu
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y --no-install-recommends libgomp1
        getent group soul-memory-tls >/dev/null || groupadd --system soul-memory-tls
        usermod -aG soul-memory-tls qdrant
        usermod -aG soul-memory-tls redis
        chown root:soul-memory-tls /etc/soul-memory
        chmod 0750 /etc/soul-memory
        chown root:soul-memory-tls /etc/soul-memory/server.key
        chmod 0640 /etc/soul-memory/server.key
        chown root:qdrant /etc/qdrant
        chmod 0750 /etc/qdrant
        chown root:redis /usr/lib/falkordb
        chmod 0750 /usr/lib/falkordb
        sed -i 's#--config-path /etc/qdrant/config\(\.yaml\)\{0,1\}#--config-path /etc/qdrant/config.yaml#' /etc/systemd/system/qdrant.service
        sed -i '/StartLimitIntervalSec=/d; /StartLimitBurst=/d' /etc/systemd/system/qdrant.service
        touch /var/log/redis/redis-server.log
        chown redis:adm /var/log/redis/redis-server.log
        chmod 0640 /var/log/redis/redis-server.log
        install -d -m 0755 /etc/systemd/system/redis-server.service.d
        cat > /etc/systemd/system/redis-server.service.d/60-lxc-compat.conf <<'EOF'
        [Service]
        PrivateUsers=false
        EOF
        systemctl daemon-reload
        systemctl reset-failed qdrant redis-server
        systemctl restart nftables qdrant redis-server
        systemctl is-active --quiet nftables qdrant redis-server
      SH
    end

    def ssh(config, command)
      ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", config.fetch("target_alias"), command]
    end

    def capture(command)
      stdout, stderr, status = Open3.capture3(*command)
      {"success" => status.success?, "stdout" => stdout, "stderr" => stderr}
    end

    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    def canonicalize(value) = value.is_a?(Hash) ? value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] } : value.is_a?(Array) ? value.map { |item| canonicalize(item) } : value
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |sum, pair| sum | (pair[0] ^ pair[1]) }.zero?
    def bounded(value) = value.to_s.byteslice(0, 4096).to_s
    def outcome(ok, lifecycle, reason, data, mutation = "none") = {"ok" => ok, "lifecycle_state" => lifecycle, "schema" => SCHEMA, "reason" => reason, "data" => data, "mutation" => mutation}
  end
end
