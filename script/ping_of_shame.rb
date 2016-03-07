#!/usr/bin/ruby

# require "pry"
# require "awesome_print"
require "slack-notifier"
require "time"
require "action_view"
require "action_view/helpers"

include ActionView::Helpers::DateHelper     # for time_ago_in_words

HEROKU_USER = ENV.fetch("HEROKU_USER")
SLACK_HOOK = ENV["SLACK_HOOK"]

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
  running_temporary_apps = get_running_temporary_apps
  notify_slack_about_apps(running_temporary_apps)
end

def ensure_correct_user
  current_user = `#{heroku_bin} auth:whoami`.strip

  if current_user != HEROKU_USER
    $stderr.puts "Heroku toolkit not logged in as '#{HEROKU_USER}'."
    $stderr.puts "Please log in and try again"
    exit 1
  end
end

def get_running_temporary_apps
  all_apps = `#{heroku_bin} apps -p`.strip.split("\n") # note: this includes "=== My Apps"

  app_names = all_apps.map { |app_name| app_name.split(/\s+/)[0] }
  temporary_apps = select_temporary_apps(app_names)

  running_temporary_apps = []
  first = true
  temporary_apps.each do |app_name|
    sleep 1 if !first     # let's rate limit ourselves
    app_status_json = `#{heroku_bin} apps:info -j --app "#{app_name}"`
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
      running_temporary_apps << {
        app_name: app_name,
        created_at: created_at,
        cost: cost
      }
    end
    first = false
  end

  running_temporary_apps
end

def notify_slack_about_apps(running_temporary_apps)
  return if !running_temporary_apps.any?

  message = ":money_with_wings::heroku::bell: Warning, the following temporary apps are running :bell::heroku::money_with_wings:"
  running_temporary_apps.each do |app|
    time_ago = time_ago_in_words(app[:created_at])

    message << "\n#{app[:app_name]} - Running for #{time_ago} - cost so far: #{app[:cost]}"
  end
  message << "\nhttp://media.giphy.com/media/l41lP9PkGs7yhg9s4/giphy.gif"

  if SLACK_HOOK.nil?
    puts "Printing out slack message instead of sending to slack because the SLACK_HOOK env var isn't set"
    puts message
  else
    notifier = Slack::Notifier.new(SLACK_HOOK, username: ENV.fetch("SLACK_USERNAME", "pingOfShame"))

    notifier.ping message
  end

end

def select_temporary_apps(apps)
  apps.select { |app_name| app_name.start_with?("boundless-canvas") }
end

def heroku_bin
  @heroku_bin ||= begin
    buildpack_bin = "bin/heroku/bin/heroku"
    if File.exist?(buildpack_bin)
      buildpack_bin
    else
      bin = `which heroku`.strip
      if !bin.nil? && bin != ""
        bin
      else
        raise "unable to find heroku bin"
      end
    end
  end
end

run
