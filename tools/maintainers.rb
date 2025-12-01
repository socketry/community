#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

# Basic configuration (can be overridden with env vars):
ORG        = ENV.fetch("GITHUB_ORG", "socketry")
TEAM_SLUG  = ENV.fetch("GITHUB_TEAM", "maintainers")
PERMISSION = ENV.fetch("GITHUB_PERMISSION", "maintain") # pull|triage|push|maintain|admin

dry_run          = ARGV.delete("--dry-run")
include_archived = ARGV.delete("--include-archived")

def run_cmd(*cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  unless status.success?
    warn "Command failed: #{cmd.join(' ')}"
    warn stderr unless stderr.empty?
    exit status.exitstatus
  end
  stdout
end

puts "Org:        #{ORG}"
puts "Team slug:  #{TEAM_SLUG}"
puts "Permission: #{PERMISSION}"
puts "Dry run:    #{dry_run ? 'yes' : 'no'}"
puts "Archived:   #{include_archived ? 'include' : 'skip'}"
puts

# 1. Fetch repos (name + archived flag) from gh:
repos_json = run_cmd(
  "gh", "repo", "list", ORG,
  "--limit", "1000",
  "--json", "name,isArchived",
  "--jq", "."
)

repos = JSON.parse(repos_json, symbolize_names: true)

if repos.empty?
  puts "No repositories found for org #{ORG}."
  exit 0
end

puts "Found #{repos.size} repos in #{ORG}."
puts

# 2. Process each repo:
updated = 0
skipped_archived = 0

repos.each do |repo|
  name       = repo[:name]
  archived   = repo[:isArchived]
  full_name  = "#{ORG}/#{name}"

  if archived && !include_archived
    skipped_archived += 1
    puts "[skip archived] #{full_name}"
    next
  end

  puts "[update] Setting team '#{TEAM_SLUG}' => '#{PERMISSION}' on #{full_name}"

  if dry_run
    next
  end

  api_cmd = [
    "gh", "api",
    "--method", "PUT",
    "/orgs/#{ORG}/teams/#{TEAM_SLUG}/repos/#{ORG}/#{name}",
    "-f", "permission=#{PERMISSION}"
  ]

  success = system(*api_cmd)

  unless success
    warn "  -> FAILED on #{full_name}"
    next
  end

  updated += 1
end

puts
puts "Summary:"
puts "  Updated repos:  #{updated}"
puts "  Skipped archived: #{skipped_archived}" unless include_archived
puts "Done."
