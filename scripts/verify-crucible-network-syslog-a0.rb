#!/usr/bin/env ruby
# frozen_string_literal: true
root = File.expand_path('..', __dir__)
base = File.join(root, 'deploy', 'network-syslog', 'crucible')
errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end
receiver = File.read(File.join(base, '10-soul-network-devices.conf'))
rotation = File.read(File.join(base, 'soul-network-devices.logrotate'))
status = File.read(File.join(base, 'soul-network-syslog-status'))
wazuh = File.read(File.join(base, 'wazuh-localfile.xml'))
installer = File.read(File.join(base, 'install.sh'))
check.call('receiver binds only the Crucible private address and UDP 514', receiver.include?('address="192.168.124.2" port="514"') && !receiver.include?('imtcp'))
check.call('only Lattice and Loom enter fixed files', %w[192.168.124.10 192.168.124.11 lattice.log loom.log].all? { |value| receiver.include?(value) } && receiver.scan('if $fromhost-ip').length == 2)
check.call('bounded in-memory queue and input rate limit are explicit', receiver.include?('queue.type="FixedArray"') && receiver.include?('queue.size="10000"') && receiver.include?('rateLimit.interval="5"') && receiver.include?('rateLimit.burst="500"') && !receiver.match?(/queue\.filename|disk/i))
check.call('retention is compressed, daily, fourteen rotations, and size bounded', %w[daily compress delaycompress].all? { |value| rotation.include?(value) } && rotation.include?('rotate 14') && rotation.include?('maxsize 50M'))
check.call('status is read-only and enforces the private listener and two GiB threshold', status.include?('192.168.124.2:514') && status.include?('2 * 1024 * 1024 * 1024') && !status.match?(/\brm\b|firewall-cmd|systemctl\s+(start|restart|enable)/))
check.call('Wazuh input is passive, future-only, and file based', wazuh.include?('/var/log/network-devices/*.log') && wazuh.include?('<log_format>syslog</log_format>') && wazuh.include?('<only-future-events>yes</only-future-events>') && !wazuh.match?(/active-response|command/i))
check.call('installer validates configs before opening the firewall', installer.index('rsyslogd -N1') < installer.index('firewall-cmd --get-zone-of-interface') && installer.index('wazuh-logcollector -t') < installer.index('firewall-cmd --get-zone-of-interface'))
check.call('firewall rules use the same two exact sources and rollback removes them', installer.include?('for source in 192.168.124.10 192.168.124.11') && installer.include?('--add-rich-rule') && installer.include?('--remove-rich-rule'))
check.call('backup repository and arbitrary relay remain absent', ![receiver, rotation, status, wazuh, installer].join.include?('/srv/soul-backup') && !receiver.match?(/omfwd|@@|action\s*\([^\)]*target=/i))
abort("Crucible network syslog A0 verification failed: #{errors.join(', ')}") unless errors.empty?
puts 'Crucible network syslog A0 verification passed.'
