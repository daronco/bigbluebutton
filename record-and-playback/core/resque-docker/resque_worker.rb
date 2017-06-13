require 'resque'
require File.expand_path('../../lib/recordandplayback', __FILE__)

RAP_ROOT ||= File.expand_path('../../..', __FILE__)

module BigBlueButton
  class ResqueWorker
    @queue = 'recordings:process'

    def self.perform(meeting_id)
      self.set_logger
      BigBlueButton.logger.info("Worker for #{meeting_id}: Starting...")

      cmd = self.process_and_publish_cmd(meeting_id)
      BigBlueButton.logger.info("Worker for #{meeting_id}: Will run '#{cmd}'")
      system(cmd)
      BigBlueButton.logger.info("Worker for #{meeting_id}: Finished with exit code #{$?}")
    end

    # Set BigBlueButton.logger to the default file
    def self.set_logger
      path = File.join(RAP_ROOT, 'core', 'scripts', 'bigbluebutton.yml')
      props = YAML::load(File.open(path))
      log_dir = props['log_dir']
      logger = Logger.new("#{log_dir}/bbb-rap-worker.log")
      logger.level = Logger::INFO
      BigBlueButton.logger = logger
    end

    def self.process_and_publish_cmd(meeting_id)
      # the rap scripts require you to run them from their folder, otherwise things will break
      path = File.join(RAP_ROOT, 'core', 'scripts')

      cmd_process = "ruby rap-process-worker.rb -m #{meeting_id}"
      cmd_publish = "ruby rap-publish-worker.rb -m #{meeting_id}"
      "cd #{path} && #{cmd_process} && #{cmd_publish}"
    end
  end
end
