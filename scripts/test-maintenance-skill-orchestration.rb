# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/soul_core/maintenance_skill_service"
require_relative "../lib/soul_core/application_facade"

class MaintenanceSkillTest < Minitest::Test
  class Fleet
    attr_accessor :required, :control, :ok
    attr_reader :refreshes
    def initialize
      @required, @control, @ok, @refreshes = false, "maintenance", true, []
    end
    def snapshot
      {"ok" => true, "lifecycle_state" => "complete", "data" => {"devices" => [
        {"id" => "managed_test", "label" => "Crucible", "control" => @control, "status" => "healthy",
         "facts" => {"control_target_id" => "crucible"}, "reboot" => {"required" => @required}},
        {"id" => "workstation", "label" => "Atelier", "control" => "maintenance",
         "facts" => {"control_target_id" => "workstation"}}]}}
    end
    def refresh(device_id:, schedule_recovery:)
      @refreshes << [device_id, schedule_recovery]
      r = snapshot
      r["ok"] = @ok
      r["data"]["refreshed_device_id"] = device_id
      r
    end
  end
  class Controller
    attr_reader :calls
    def initialize = @calls = []
    def preview(**args)
      @calls << [:preview, args]
      {"ok" => true, "lifecycle_state" => "complete", "data" => {"plan" => args}}
    end
    def execute(**args)
      @calls << [:execute, args]
      {"ok" => args[:expected_digest] == "reviewed", "lifecycle_state" => args[:expected_digest] == "reviewed" ? "complete" : "blocked_for_human_review",
       "data" => {"receipt" => {"receipt_id" => "fixture"}}}
    end
  end
  def setup
    @fleet, @control = Fleet.new, Controller.new
    @service = SoulCore::MaintenanceSkillService.new(fleet_status_service: @fleet, device_control_service: @control)
  end
  def execute(action = "maintenance", digest = "reviewed")
    @service.execute(device_id: "crucible", action: action, confirmation: "EXACT", expected_digest: digest)
  end
  def test_maintenance_never_reboots_and_preserves_exact_controller_arguments
    @fleet.required = true
    result = execute
    assert_equal "required", result.dig("data", "reboot_followup", "state")
    assert_equal "maintenance.reboot", result.dig("data", "reboot_followup", "suggested_skill")
    assert_equal false, result.dig("data", "reboot_followup", "automatic_execution")
    assert_equal ["maintenance"], @control.calls.map { |_, args| args[:action] }
    assert_equal "EXACT", @control.calls.first.last[:confirmation]
    assert_equal [["managed_test", false], ["managed_test", false]], @fleet.refreshes
  end
  def test_false_and_unknown_never_propose_reboot
    [false, nil, "true"].each do |value|
      @fleet.required = value
      result = execute
      assert_nil result.dig("data", "reboot_followup", "suggested_skill")
      assert_equal value == false ? "not_required" : "unknown", result.dig("data", "reboot_followup", "state")
      count = @control.calls.length
      refute @service.preview(device_id: "crucible", action: "reboot")["ok"]
      refute execute("reboot")["ok"]
      assert_equal count, @control.calls.length
    end
  end
  def test_reboot_is_separate_and_rechecks_requirement_at_execute
    @fleet.required = true
    assert @service.preview(device_id: "crucible", action: "reboot")["ok"]
    @fleet.required = false
    refute execute("reboot")["ok"]
    assert_equal [:preview], @control.calls.map(&:first)
    @fleet.required = true
    assert execute("reboot")["ok"]
    assert_equal "reboot", @control.calls.last.last[:action]
  end
  def test_atelier_unknown_inventory_only_and_refresh_failure_do_not_reach_controller
    %w[workstation atelier unknown].each { |id| refute @service.preview(device_id: id, action: "maintenance")["ok"] }
    assert_empty @fleet.refreshes
    @fleet.control = "inventory_only"
    refute execute["ok"]
    @fleet.control = "maintenance"
    @fleet.ok = false
    refute execute["ok"]
    assert_empty @control.calls
  end
  def test_controller_refusal_propagates_without_followup_or_retry
    result = execute("maintenance", "stale")
    refute result["ok"]
    assert_nil result.dig("data", "reboot_followup")
    assert_equal 1, @control.calls.length
  end
  def test_public_operations_fix_action_and_reject_action_override
    Dir.mktmpdir do |root|
      facade = SoulCore::ApplicationFacade.new(root: root, maintenance_fleet_status_service: @fleet, maintenance_device_control_service: @control)
      request = {"schema_version" => "soul.application.v1", "request_id" => "skill_preview_0001",
        "operation" => "maintenance.skill.preview", "parameters" => {"device_id" => "crucible"}, "context" => {"interface" => "internal"}}
      assert facade.call(request)["ok"]
      assert_equal "maintenance", @control.calls.last.last[:action]
      refute facade.call(request.merge("request_id" => "skill_preview_0002", "parameters" => {"device_id" => "crucible", "action" => "reboot"}))["ok"]
    end
  end

  def test_hypervisor_guest_changes_invalidate_reboot_digest
    Dir.mktmpdir do |root|
      fleet = Object.new
      guests = [{"id" => 200, "type" => "qemu", "name" => "backup", "status" => "running"}]
      fleet.define_singleton_method(:snapshot) do
        {"ok" => true, "lifecycle_state" => "complete", "data" => {"devices" => [
          {"id" => "forge", "facts" => {"guests" => guests}}]}}
      end
      controller = SoulCore::MaintenanceDeviceControlService.new(root: root, fleet_status_service: fleet)
      first = controller.preview(device_id: "forge", action: "reboot").dig("data", "plan")
      assert first["impact"].any? { |i| i.include?("backup") }
      assert first["impact"].any? { |i| i.include?("do not verify every guest application") }
      guests.first["status"] = "stopped"
      second = controller.preview(device_id: "forge", action: "reboot").dig("data", "plan")
      refute_equal first["expected_digest"], second["expected_digest"]
    end
  end
end
