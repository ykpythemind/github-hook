
require "sinatra"

SCRIPT_FILE = (ENV["SCRIPT_FILE"] || "test.sh").freeze
SCRIPT_DIR = 'scripts'.freeze

if ENV["SCRIPT_PATH"]
  SCRIPT_PATH = ENV["SCRIPT_PATH"]
else
  SCRIPT_PATH = File.expand_path("../#{SCRIPT_DIR}/#{SCRIPT_FILE}", __FILE__)
end

abort "SCRIPT_FILE not found" unless File.exist? SCRIPT_PATH

LOG_PATH = ENV["LOG_PATH"]
SECRET = ENV["SECRET"]

post '/' do
  if request.env["HTTP_X_GITHUB_EVENT"] != "push"
    halt 200, "Event is not push"
  end

  request.body.rewind
  payload = request.body.read
  verify_signature payload

  hash = JSON.parse payload

  if hash["ref"] != "refs/heads/master"
    halt 200, "Not master branch"
  end

  if skip_script?(hash)
    halt 200, "Skipped."
  end

  spawn "#{SCRIPT_PATH}"

  body "script executed"
end

get '/' do
  body "alive"
end

get '/log' do
  if !LOG_PATH || !File.exist?(LOG_PATH)
    halt 404, "Not found log file"
  end

  # tail したいので手抜き
  lines = `tail -n 100 #{LOG_PATH}`.chomp.split("\n")
  body html(
    ["<h1>tailing log</h1><ul>",
      *lines.map { |line| "<li>#{line}</li>" },
      "</ul>"].join)
end


def skip_script?(payload)
  commits = payload["commits"]
  return false if commits.empty?
  commits.any? do |commit|
    commit["message"].include? "[ci skip]"
  end
end

def html(body)
  """
  <!DOCTYPE html>
  <html lang=\"en\">
  <head>
    <meta charset=\"UTF-8\">
    <title></title>
  </head>
  <body>
    #{body}
  </body>
  </html>
  """
end

def verify_signature(payload_body)
  # https://developer.github.com/webhooks/securing/#validating-payloads-from-github
  return unless SECRET
  signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), SECRET, payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
end


