#!/usr/bin/ruby
# encoding: UTF-8

RAP_ROOT ||= File.expand_path('../../../..', __FILE__)

require "trollop"
require File.join(RAP_ROOT, 'core', 'lib', 'recordandplayback')
require File.join(RAP_ROOT, 'core', 'resque-docker', 'resque_worker')

opts = Trollop::options do
  opt :meeting_id, "Meeting id archived", :type => String
end
meeting_id = opts[:meeting_id]

logger = Logger.new("/var/log/bigbluebutton/bbb-rap-worker.log")
logger.level = Logger::INFO
BigBlueButton.logger = logger

path = File.join(RAP_ROOT, 'core', 'scripts', 'bigbluebutton.yml')
props = YAML::load(File.open(path))
recording_dir = "#{props['recording_dir']}/raw/#{meeting_id}"

# new props with the user/host to be used to copy files from this server
if props['remote_process']
  host = "ssh://#{props['copy_from_user']}@#{props['copy_from_host']}"
end

BigBlueButton.logger.info("Enqueuing job to process meeting #{meeting_id}")
Resque.enqueue(BigBlueButton::ResqueWorker, meeting_id, recording_dir, host)

exit 0
