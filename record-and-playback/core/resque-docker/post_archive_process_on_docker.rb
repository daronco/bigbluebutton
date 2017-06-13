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

BigBlueButton.logger.info("Enqueuing job to process meeting #{meeting_id}")
Resque.enqueue(BigBlueButton::ResqueWorker, meeting_id)

exit 0
