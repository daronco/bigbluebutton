require 'resque'
require 'net/scp'
require 'uri'
require File.expand_path('../../lib/recordandplayback', __FILE__)

RAP_ROOT ||= File.expand_path('../../..', __FILE__)

module BigBlueButton
  class ResqueWorker
    @queue = 'recordings:process'

    def self.perform(meeting_id, recording_dir, host)
      worker = BigBlueButton::ResqueWorker.new(meeting_id, recording_dir, host)
      worker.perform
    end

    def initialize(meeting_id, recording_dir, host)
      @meeting_id = meeting_id
      @recording_dir = recording_dir
      @host = host # if nil will try local files
    end

    def perform
      self.load_configs
      self.pull_files unless @host.nil?
      self.process_and_publish
    end

    # Load the default configurations used by rap scripts
    def load_configs
      path = File.join(RAP_ROOT, 'core', 'scripts', 'bigbluebutton.yml')
      @props = YAML::load(File.open(path))
      log_dir = @props['log_dir']
      logger = Logger.new("#{log_dir}/bbb-rap-worker.log")
      logger.level = Logger::INFO
      BigBlueButton.logger = logger
    end

    # Pull files from the remote server
    def pull_files
      uri = URI.parse(@host)
      local_dir = "#{@props['recording_dir']}/raw"

      BigBlueButton.logger.info("Worker for #{@meeting_id}: Downloading #{uri.user}@#{uri.host}:#{@recording_dir} into #{local_dir}")
      Net::SCP.download!(uri.host, uri.user, @recording_dir, local_dir, :recursive => true)

      # create a .done file so the rap scripts actually consider the recording
      FileUtils.mkdir_p "#{@props['recording_dir']}/status/sanity"
      FileUtils.touch "#{@props['recording_dir']}/status/sanity/#{@meeting_id}.done"
    end

    # Triggers the process and publish scripts
    def process_and_publish
      cmd = self.process_and_publish_cmd
      BigBlueButton.logger.info("Worker for #{@meeting_id}: Running '#{cmd}'")
      system(cmd)
      BigBlueButton.logger.info("Worker for #{@meeting_id}: Finished with exit code #{$?}")
    end

    def process_and_publish_cmd
      # the rap scripts require you to run them from their folder, otherwise things will break
      path = File.join(RAP_ROOT, 'core', 'scripts')

      cmd_process = "ruby rap-process-worker.rb -m #{@meeting_id}"
      cmd_publish = "ruby rap-publish-worker.rb -m #{@meeting_id}"
      "cd #{path} && #{cmd_process} && #{cmd_publish}"
    end
  end
end
