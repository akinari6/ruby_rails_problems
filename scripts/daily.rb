#!/usr/bin/env ruby
# frozen_string_literal: true

# 毎朝 1 回実行される。
#   1. 未着手の day PR が開いていなければ、次の Day の問題 PR を作る
#   2. マージ済みの day PR について、マージから 1 / 7 / 30 日後に復習 PR を作る
#
# 環境変数:
#   GH_TOKEN     gh CLI 用トークン（Actions では github.token）
#   BASE_BRANCH  PR のベース（デフォルトブランチ）
#   DRY_RUN=1    git / gh を実行せず、代わりにコマンドを表示する
#   PR_LIST_JSON テスト用。gh pr list の結果を差し替える

require "json"
require "date"
require "time"
require "fileutils"

REVIEW_INTERVALS = [1, 7, 30].freeze
JST_OFFSET = "+09:00"
BASE = ENV.fetch("BASE_BRANCH", "main")
DRY = ENV["DRY_RUN"] == "1"

def sh(*cmd)
  puts "+ #{cmd.join(' ')}"
  return if DRY
  system(*cmd) || abort("command failed: #{cmd.join(' ')}")
end

def gh_json(*args)
  if ENV["PR_LIST_JSON"] && args.first == "pr" && args[1] == "list"
    return JSON.parse(ENV["PR_LIST_JSON"])
  end
  out = IO.popen(["gh", *args], &:read)
  abort("gh failed: #{args.join(' ')}") unless $?.success?
  JSON.parse(out)
end

def ensure_labels
  { "day" => "0E8A16", "review" => "FBCA04" }.each do |name, color|
    sh "gh", "label", "create", name, "--color", color, "--force",
       "--description", (name == "day" ? "その日の問題" : "復習（1/7/30 日後）")
  end
end

def create_pr(branch:, src:, dest:, title:, body:, label:)
  sh "git", "checkout", "-q", "-B", branch, "origin/#{BASE}"
  unless DRY
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(src, dest)
  end
  sh "git", "add", dest
  sh "git", "commit", "-q", "-m", title
  # day/* と review/* はこのスクリプトだけが作るブランチなので、前回の実行が
  # PR 作成前に失敗して残っていても上書きして再実行できるようにする
  sh "git", "push", "-u", "--force", "origin", branch
  body_file = "/tmp/pr_body_#{branch.tr('/', '_')}.md"
  File.write(body_file, body) unless DRY
  sh "gh", "pr", "create", "--base", BASE, "--head", branch,
     "--title", title, "--body-file", body_file, "--label", label
  sh "git", "checkout", "-q", BASE
end

today = Time.now.getlocal(JST_OFFSET).to_date
puts "today (JST): #{today}"

sh "git", "config", "user.name", "github-actions[bot]"
sh "git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"
ensure_labels

prs = gh_json("pr", "list", "--state", "all", "--limit", "500",
              "--json", "number,headRefName,state,mergedAt")
day_prs    = prs.select { |pr| pr["headRefName"] =~ %r{\Aday/(\d+)\z} }
review_prs = prs.select { |pr| pr["headRefName"] =~ %r{\Areview/day(\d+)-r(\d+)\z} }

# ---- 1. 次の Day ----
if day_prs.any? { |pr| pr["state"] == "OPEN" }
  open_pr = day_prs.find { |pr| pr["state"] == "OPEN" }
  puts "skip new day: PR ##{open_pr['number']} (#{open_pr['headRefName']}) is still open"
else
  next_day = (day_prs.map { |pr| pr["headRefName"][%r{\d+}].to_i }.max || 0) + 1
  nn  = format("%02d", next_day)
  src = "bank/day#{nn}/problem.md"
  if File.exist?(src)
    body = <<~BODY
      Day #{nn} の問題です。所要時間の目安は 20 分。

      ### 回答のしかた

      - **A. 出力予測**: コードブロックの最後の行にインラインコメントで、予測した出力を書く
      - **B. コードレビュー**: 問題のある行にインラインコメントで指摘を書く（実際のレビューと同じ要領で）
      - **C. PRレビュー**: 「Files changed」からレビューを開始し、Approve / Request changes のどちらかを選んで理由を書く
      - 書き終えたら、この PR に `/answer` とコメントする → 解答・解説が投稿され、この PR はマージされます

      復習 PR は、マージの #{REVIEW_INTERVALS.join(' / ')} 日後に自動で開きます。
    BODY
    create_pr(branch: "day/#{nn}", src: src, dest: "days/day#{nn}/problem.md",
              title: "Day #{nn}", body: body, label: "day")
  else
    puts "bank is exhausted: #{src} not found (next day would be #{nn})"
  end
end

# ---- 2. 復習 ----
day_prs.select { |pr| pr["mergedAt"] }.each do |pr|
  nn = format("%02d", pr["headRefName"][%r{\d+}].to_i)
  merged_on = Time.parse(pr["mergedAt"]).getlocal(JST_OFFSET).to_date
  elapsed = (today - merged_on).to_i

  if review_prs.any? { |r| r["state"] == "OPEN" && r["headRefName"].start_with?("review/day#{nn}-") }
    puts "skip review for day#{nn}: a review PR is still open"
    next
  end

  REVIEW_INTERVALS.each do |interval|
    branch = "review/day#{nn}-r#{interval}"
    next if review_prs.any? { |r| r["headRefName"] == branch }
    next if elapsed < interval

    src = "bank/day#{nn}/problem.md"
    body = <<~BODY
      Day #{nn} の復習です（マージから #{interval} 日後、実際の経過: #{elapsed} 日）。元の PR: ##{pr['number']}

      元の PR の自分のコメントと解答は**見ずに**、もう一度最初から解いてください。
      回答のしかたは元の PR と同じです。書き終えたら `/answer` とコメントしてください。
    BODY
    create_pr(branch: branch, src: src, dest: "reviews/day#{nn}/r#{interval}/problem.md",
              title: "復習 Day #{nn}（#{interval} 日後）", body: body, label: "review")
    break # 1 日に 1 つずつ
  end
end
