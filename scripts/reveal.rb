#!/usr/bin/env ruby
# frozen_string_literal: true

# PR に `/answer` とコメントされたときに実行される。
#   1. その PR に対応する bank/dayNN/answer.md をコメントとして投稿する
#   2. PR をマージする（復習 PR の起点となる mergedAt が記録される）
#
# 環境変数:
#   GH_TOKEN   gh CLI 用トークン
#   PR_NUMBER  対象 PR 番号

require "json"

pr_number = ENV.fetch("PR_NUMBER")

def sh(*cmd)
  puts "+ #{cmd.join(' ')}"
  system(*cmd) || abort("command failed: #{cmd.join(' ')}")
end

out = IO.popen(["gh", "pr", "view", pr_number, "--json", "headRefName,state"], &:read)
abort("gh pr view failed") unless $?.success?
pr = JSON.parse(out)

m = pr["headRefName"].match(%r{\A(?:day/(\d+)|review/day(\d+)-r\d+)\z})
abort("not a problem PR: #{pr['headRefName']}") unless m
nn = format("%02d", (m[1] || m[2]).to_i)

answer_path = "bank/day#{nn}/answer.md"
abort("answer not found: #{answer_path}") unless File.exist?(answer_path)

body_file = "/tmp/answer_#{pr_number}.md"
File.write(body_file, File.read(answer_path) + "\n\n---\n_`/answer` により自動投稿。復習 PR はマージの 1 / 7 / 30 日後に自動で開きます。_\n")
sh "gh", "pr", "comment", pr_number, "--body-file", body_file

if pr["state"] == "OPEN"
  sh "gh", "pr", "merge", pr_number, "--merge", "--delete-branch"
else
  puts "PR ##{pr_number} is #{pr['state']}; skip merge"
end
