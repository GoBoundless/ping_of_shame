#!/usr/bin/ruby

# require "pry"
# require "awesome_print"
require "slack-notifier"
require "time"
require "action_view"
require "action_view/helpers"

include ActionView::Helpers::DateHelper     # for time_ago_in_words

HEROKU_USER = ENV.fetch("HEROKU_USER")
SLACK_HOOK = ENV.fetch("SLACK_HOOK")
HEROKU_BIN = "bin/heroku/bin/heroku"      # installed by the buildpack

DYNO_COSTS = {
  "free" => 0,
  "hobby" => 0,
  "standard-1x" => 25,
  "standard-2x" => 50,
  "performance-m" => 250,
  "performance-l" => 500,
}

def run
  ensure_correct_user
  running_canvas_apps = get_running_canvas_apps
  notify_slack_about_apps(running_canvas_apps)
end

def ensure_correct_user
  current_user = `#{HEROKU_BIN} auth:whoami`.strip

  if current_user != HEROKU_USER
    $stderr.puts "Heroku toolkit not logged in as '#{HEROKU_USER}'."
    $stderr.puts "Please log in and try again"
    exit 1
  end
end

def get_running_canvas_apps
  all_apps = `#{HEROKU_BIN} apps -p`.strip.split("\n") # note: this includes "=== My Apps"

  canvas_apps = all_apps.select { |app_name| app_name.start_with?("boundless-canvas") }.map { |app_name| app_name.split(/\s+/)[0] }

  running_canvas_apps = []
  first = true
  canvas_apps.each do |app_name|
    sleep 1 if !first     # let's rate limit ourselves
    app_status_json = `#{HEROKU_BIN} apps:info -j --app "#{app_name}"`
    app_status = JSON.parse(app_status_json)
    app_dynos = app_status["dynos"]
    if app_dynos.any?
      created_at = app_dynos.map { |dyno| Time.parse(dyno["created_at"]) }.min
      cost_list = app_dynos.map { |dyno| DYNO_COSTS[dyno["size"].downcase] }
      if cost_list.any? { |cost| cost.nil? }
        cost = "unknown - unknown dyno type"
      else
        monthly_cost = cost_list.sum
        cost_per_second = monthly_cost.to_f / (30 * 24 * 60 * 60)
        seconds_run = Time.now - created_at
        cost = sprintf("$%0.02f", cost_per_second * seconds_run)
      end
      running_canvas_apps << {
        app_name: app_name,
        created_at: created_at,
        cost: cost
      }
    end
    first = false
  end

  running_canvas_apps
end

def notify_slack_about_apps(running_apps)
  return if !running_apps.any?

  notifier = Slack::Notifier.new(SLACK_HOOK, username: ENV.fetch("SLACK_USERNAME", "pingOfShame"))

  message = ":money_with_wings::heroku::bell: Warning, the following canvas apps are running :bell::heroku::money_with_wings:"
  running_apps.each do |app|
    time_ago = time_ago_in_words(app[:created_at])

    message << "\n#{app[:app_name]} - Running for #{time_ago} - cost so far: #{app[:cost]}"
  end
  message << "\nhttp://media.giphy.com/media/l41lP9PkGs7yhg9s4/giphy.gif"
  notifier.ping message
end

run
