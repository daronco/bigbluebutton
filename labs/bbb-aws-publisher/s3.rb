# Set encoding to utf-8
# encoding: UTF-8

require 'rubygems'
require 'aws-sdk'
require 'pathname'
require 'redis'
require 'json'
require 'logger'
require 'yaml'
require 'uri'
require 'nokogiri'
require 'stringio'
require 'trollop'
require 'pp'

module BigBlueButtonAwsRecorder
  # Logs information about its progress.
  # Replace with your own logger if you desire.
  #
  # @param [Logger] log your own logger
  # @return [Logger] the logger you set
  def self.logger=(log)
    @logger = log
  end

  # Get logger.
  #
  # @return [Logger]
  def self.logger
    return @logger if @logger
    logger = Logger.new(STDOUT)
    logger.level = Logger::INFO
    @logger = logger
  end

  class Publisher
    def initialize(aws_key = ENV['AWS_KEY'], aws_secret = ENV['AWS_SECRET'], aws_region = ENV['AWS_REGION'])
      @s3 = Aws::S3::Resource.new(
        credentials: Aws::Credentials.new(aws_key, aws_secret),
        region: aws_region
      )
      @cloud_front = Aws::CloudFront::Client.new(
        credentials: Aws::Credentials.new(aws_key, aws_secret),
        region: aws_region
      )
      @distribution_id = Hash.new
    end

    def publish(record_id, published_dir, bucket_name, formats = nil)
      publish_helper(record_id, published_dir, bucket_name, true, formats)
    end

    def unpublish(record_id, published_dir, bucket_name, formats = nil)
      publish_helper(record_id, published_dir, bucket_name, false, formats)
    end

    def delete(record_id, published_dir, bucket_name)
      BigBlueButtonAwsRecorder.logger.info "Deleting recording #{record_id}"
      prefixes = get_prefixes(record_id, published_dir)
      success = true
      keys = []
      invalidate_cache_list = []
      prefixes.each do |prefix|
        BigBlueButtonAwsRecorder.logger.info "Processing prefix #{prefix}"
        @s3.bucket(bucket_name).objects(prefix: prefix).each do |obj|
          BigBlueButtonAwsRecorder.logger.info "Deleting #{obj.key}"
          keys << {
            key: obj.key
          }
        end
      end
      keys.each_slice(1000) do |keys_slice|
        output = @s3.bucket(bucket_name).delete_objects({
          delete: {
            objects: keys_slice
          }
        })
        local_success = output.deleted.length == keys_slice.length && output.errors.length == 0
        if local_success
          BigBlueButtonAwsRecorder.logger.info "Successfully deleted #{keys_slice.length} objects"
        else
          BigBlueButtonAwsRecorder.logger.error "Failed to delete #{output.errors.length} of #{keys_slice.length}"
        end
        invalidate_cache_list << "#{prefix}/*" if output.deleted.length > 0
        success &= local_success
      end
      invalidate_cache(bucket_name, invalidate_cache_list.uniq)
      BigBlueButtonAwsRecorder.logger.info "Recording #{record_id} deleted successfully" if success
      success
    end

    def upload_playbacks(playback_dir, bucket_name)
      success = true
      playbacks = Dir.glob("#{playback_dir}/*").select { |d| File.directory?(d) }
      playbacks.each do |playback_dir|
        prefix_parent = File.expand_path("#{playback_dir}/../..")
        prefix = path_relative_to(playback_dir, prefix_parent)
        BigBlueButtonAwsRecorder.logger.info "Updating playback format #{prefix}"
        success &= compare_and_push(prefix, playback_dir, prefix_parent, bucket_name, true)
      end
      BigBlueButtonAwsRecorder.logger.info "Playbacks updated successfully" if success
      success
    end

    def get_modified_link(link)
      uri = URI.parse(link)
      "#{$playback_protocol}://#{$playback_host}#{uri.request_uri}"
    end

    private

    def compare_and_push(remote_prefix, local_dir, local_prefix, bucket_name, set_public)
      success = true
      local_md5 = load_local_md5sums(local_dir)
      remote_md5 = load_remote_md5sums(bucket_name, "#{remote_prefix}/MD5SUMS")
      modified_files = Hash[*(local_md5.to_a - remote_md5.to_a).flatten].keys
      updated_md5 = remote_md5.merge(local_md5)
      # we might avoid to record the file again if it's the same as local_md5
      record_md5sums_file(local_dir, updated_md5)
      if updated_md5 != remote_md5
        modified_files = modified_files + [ "MD5SUMS" ]
      end

      if modified_files.empty?
        BigBlueButtonAwsRecorder.logger.info "No need to push files to AWS"
      else
        # only invalidate cache of the files already in the remote but modified
        invalidate_cache_list = (modified_files & remote_md5.keys).map{ |file| "#{remote_prefix}/#{file}" }

        modified_files.map!{ |file| "#{remote_prefix}/#{file}" }

        files = key_files_to_h(modified_files, local_prefix)
        success = upload_files(files, bucket_name, set_public)

        invalidate_cache(bucket_name, invalidate_cache_list)
      end
      success
    end

    def publish_helper(record_id, published_dir, bucket_name, set_public, formats = nil)
      BigBlueButtonAwsRecorder.logger.info "#{set_public ? "Publishing" : "Unpublishing"} recording #{record_id}"
      prefixes = get_prefixes(record_id, published_dir, formats)
      success = true
      prefixes.each do |prefix|
        BigBlueButtonAwsRecorder.logger.info "Processing prefix #{prefix}"

        # update link on the metadata file
        metadata_file = "#{published_dir}/#{prefix}/metadata.xml"
        next if ! File.exists?(metadata_file)

        # set acl for any existing object
        # acts like a resync, if old recordings were changed, update their permissions on s3
        if $opts[:disable_resync]
          local_success = true
        else
          local_success = set_acl(bucket_name, prefix, set_public)
        end
        local_success &= compare_and_push(prefix, "#{published_dir}/#{prefix}", published_dir, bucket_name, set_public)

        if $opts[:remote_playback]
          # update the playback links in the metadata file to use the new domain
          metadata_updated = update_metadata_link(metadata_file)
          if metadata_updated
            BigBlueButtonAwsRecorder.logger.info "Metadata updated"
            local_success &= compare_and_push(prefix, "#{published_dir}/#{prefix}", published_dir, bucket_name, set_public)
          end
        end

        if !$opts[:keep_local] && local_success
          Dir.glob("#{published_dir}/#{prefix}/**/*").each do |file|
            next if File.basename(file).include?("metadata.xml")
            BigBlueButtonAwsRecorder.logger.info "Removing local file: #{file}"
            FileUtils.rm_rf file
          end
        end
        success &= local_success
      end
      BigBlueButtonAwsRecorder.logger.info "Recording #{record_id} #{set_public ? "published" : "unpublished"} successfully" if success
      success
    end

    def update_metadata_link(metadata_file)
      FileUtils.cp(metadata_file, "#{metadata_file}.orig") if ! File.exists?("#{metadata_file}.orig")
      doc = nil
      begin
        doc = Nokogiri::XML(open(metadata_file).read)
      rescue Exception => e
        BigBlueButtonAwsRecorder.logger.error "Something went wrong: #{$!}"
        raise e
      end
      old_link = doc.at('link').content
      new_link = get_modified_link(doc.at('link').content)
      if new_link == old_link
        false
      else
        doc.at('link').content = new_link

        metadata_xml = File.new(metadata_file,"w")
        metadata_xml.write(doc.to_xml(:indent => 2))
        metadata_xml.close
        true
      end
    end

    def key_files_to_h(keys, key_prefix)
      Hash[ keys.collect { |key| [key, "#{key_prefix}/#{key}"] } ]
    end

    def get_formats(published_dir)
      Dir.glob("#{published_dir}/*").select { |d| File.directory?(d) }.map { |d| Pathname.new(d).basename.to_s }
    end

    def get_prefixes(record_id, published_dir, formats = nil)
      formats = get_formats(published_dir) if formats.nil?
      formats.map { |format| "#{format}/#{record_id}" }
    end

    def path_relative_to(path, parent)
      Pathname.new(path).relative_path_from(Pathname.new(parent)).to_s
    end

    def get_users_permission(obj)
      grant = obj.acl.grants.select { |grant| grant.grantee.uri == "http://acs.amazonaws.com/groups/global/AllUsers" }
      grant = grant.length > 0 ? grant.first.permission : nil
      grant
    end

    def md5sums_to_h(line_array)
      Hash[ line_array.map{ |line| [ line.split("  ")[1], line.split("  ")[0] ] } ]
    end

    def record_md5sums_file(dir, md5sums)
      BigBlueButtonAwsRecorder.logger.info "Writing md5sum file to #{dir}"
      Dir.chdir(dir) do
        File.open('MD5SUMS', 'w') do |file|
          md5sums.each do |filename, md5sum|
            file.write("#{md5sum}  #{filename}\n")
          end
        end
      end
      md5sums
    end

    def load_local_md5sums(dir)
      local_md5 = []
      Dir.chdir(dir) do
        local_md5 = []
        success = false
        md5_file = "MD5SUMS"
        modified_files = `find . -type f -printf "%-.22T+ %M %n %-8u %-8g %8s %Tx %.8TX %p\n" | sort -r | cut -f 2- -d ' '`.split("\n")
        if File.exists?(md5_file) && $?.exitstatus == 0 && ! modified_files.empty? && modified_files.first =~ /.*#{md5_file}$/
          BigBlueButtonAwsRecorder.logger.info "Reading #{md5_file} from file"
          local_md5 = File.read(md5_file).split("\n")
          success = true
        else
          BigBlueButtonAwsRecorder.logger.info "Calculating #{md5_file} from files"
          local_md5 = `find * ! -name '#{md5_file}' -type f -exec md5sum {} \\;`.split("\n")
          success = $?.exitstatus == 0
        end
        BigBlueButtonAwsRecorder.logger.error "Failed to load #{md5_file} for #{dir}" if ! success
      end
      md5sums_to_h(local_md5)
    end

    def load_remote_md5sums(bucket_name, key)
      io = StringIO.new
      obj = @s3.bucket(bucket_name).object(key)
      remote_md5 = {}
      if obj.exists?
        obj.get({ response_target: io })
        remote_md5 = io.readlines.map{ |line| line.strip }
      end
      md5sums_to_h(remote_md5)
    end

    def upload_files(files, bucket_name, set_public = true)
      permission = set_public ? "public-read" : "private"
      success = true
      files.each do |file_key, file_name|
        obj = @s3.bucket(bucket_name).object(file_key)
        BigBlueButtonAwsRecorder.logger.info "Uploading #{file_name}"
        begin
          local_success = obj.upload_file(file_name, acl: permission)
          BigBlueButtonAwsRecorder.logger.error "Failed while uploading #{file_name}" if ! local_success
          success &= local_success
        rescue Exception => e
          BigBlueButtonAwsRecorder.logger.error "Exception while uploading #{file_name}: #{e.message}"
          success = false
        end
      end
      success
    end

    def is_object_public?(obj)
      get_users_permission(obj) == "READ"
    end

    def set_acl(bucket_name, prefix, set_public)
      permission = set_public ? "public-read" : "private"
      invalidate_cache_list = []
      success = true
      @s3.bucket(bucket_name).objects(prefix: prefix).each do |obj|
        next if set_public == is_object_public?(obj) # skip if acl is already properly set
        BigBlueButtonAwsRecorder.logger.info "Setting #{obj.key} to #{permission}"
        obj.acl.put({
          acl: permission
        })
        local_success = ( set_public == is_object_public?(obj) )
        BigBlueButtonAwsRecorder.logger.error "Failed while setting #{obj.key} to #{permission}" if ! local_success
        # only invalidate the cache if the acl changed from public to private
        invalidate_cache_list << "#{prefix}/*" if set_public == false
        success &= local_success
      end
      invalidate_cache(bucket_name, invalidate_cache_list.uniq)
      success
    end

    def get_distribution_id(bucket_name)
      if ! @distribution_id.include?(bucket_name)
        @distribution_id[bucket_name] = nil
        BigBlueButtonAwsRecorder.logger.info "Looking for CloudFront distribution for #{bucket_name}"
        @cloud_front.list_distributions.distribution_list.items.each do |distribution|
          if distribution.status == "Deployed" && distribution.aliases.items.include?(bucket_name)
            BigBlueButtonAwsRecorder.logger.info "Found it: #{distribution.id}"
            @distribution_id[bucket_name] = distribution.id
          end
        end
      end
      @distribution_id[bucket_name]
    end

    def invalidate_cache(bucket_name, keys)
      return unless $opts[:invalidate_cache]

      return if keys.length == 0
      distribution_id = get_distribution_id(bucket_name)
      if ! distribution_id.nil?
        caller_reference = "BigBlueButtonAwsRecorder-#{Time.now.to_i}"
        keys = keys.map{ |key| "/#{key}" }
        BigBlueButtonAwsRecorder.logger.info "Invalidating cache for the keys\n#{keys.join("\n")}"
        begin
          @cloud_front.create_invalidation({
            distribution_id: distribution_id,
            invalidation_batch: {
              paths: {
                quantity: keys.length,
                items: keys
              },
              caller_reference: caller_reference
            }
          })
        rescue Exception
          BigBlueButtonAwsRecorder.logger.error "Failed to invalidate the cache: #{$!}"
          BigBlueButtonAwsRecorder.logger.info "Cache invalidation doesn't stop the daemon, keep going..."
        end
      end
    end
  end
end

def record_id_to_timestamp(r)
  r.split("-")[1].to_i / 1000
end

def path_to_record_id(r)
  File.basename(r)
end

def path_to_timestamp(r)
  record_id_to_timestamp(path_to_record_id(r))
end

# load s3.yml from the same directory as the script
props = YAML::load(File.open("#{File.dirname(File.expand_path(__FILE__))}/s3.yml"))
redis_host = props['redis_host']
redis_port = props['redis_port']
published_dir = props['published_dir']
unpublished_dir = props['unpublished_dir']
log_dir = props['log_dir']
aws_key = ENV['AWS_KEY'] || props['aws_key']
aws_secret = ENV['AWS_SECRET'] || props['aws_secret']
aws_region = ENV['AWS_REGION'] || props['aws_region']
s3_bucket = ENV['S3_BUCKET'] || props['s3_bucket']
$playback_host = props['playback_host']
$playback_protocol = props['playback_protocol']
$playback_dir = props['playback_dir']

SUB_COMMANDS = %w(upload upload-playback watch)
Trollop::options do
  banner "Host BigBlueButton recordings on Amazon's S3"
  stop_on SUB_COMMANDS
end

$cmd = ARGV.shift # get the subcommand
$opts =
  case $cmd
  when "upload"
    Trollop::options do
      opt :keep_local, "Keep local files after uploading them.", short: '-k'
      opt :disable_resync, "Disable resync of permissions for previously uploaded files.", short: '-s'
      opt :invalidate_cache, "Invalidate cache when uploading new recording files to S3. Set it when using CloudFront.", short: '-i'
      opt :remote_playback, "Update playback links in the metadata to point to the playback page hosted in S3.", short: '-r'
      opt :debug, "Send log to STDOUT instead of the log file", short: '-d'
    end
  when "upload-playback"
    Trollop::options do
      opt :debug, "Send log to STDOUT instead of the log file", short: '-d'
    end
  when "watch"
    Trollop::options do
      opt :debug, "Send log to STDOUT instead of the log file", short: '-d'
    end
  else
    Trollop::die "Unknown subcommand. Use one of: #{SUB_COMMANDS.inspect}"
  end

$opts.delete(:help)
puts "Executing '#{$cmd}' on #{s3_bucket} (#{aws_region}) with #{$opts}"

if $opts[:debug]
  logger = Logger.new(STDOUT)
  logger.level = Logger::DEBUG
  BigBlueButtonAwsRecorder.logger = logger
else
  logger = Logger.new("#{log_dir}/bbb-aws-recorder.log",'daily' )
  logger.level = Logger::INFO
  BigBlueButtonAwsRecorder.logger = logger
end

begin
  $publisher = BigBlueButtonAwsRecorder::Publisher.new(aws_key, aws_secret, aws_region)
rescue Exception => e
  BigBlueButtonAwsRecorder.logger.info "Failed to create the AWS publisher, verify your AWS settings"
  exit 1
end

# update playbacks on the bucket
if $cmd == 'upload-playback'
  $publisher.upload_playbacks($playback_dir, s3_bucket)
end

# upload existing recordings
if $cmd == 'upload'
  def collect_values(hashes)
    {}.tap{ |r| hashes.each{ |h| h.each{ |k,v| (r[k]||=[]) << v } } }
  end

  to_publish = collect_values(Dir.glob("#{published_dir}/*/*").reject{ |path| /\w+-\d+/.match(File.basename(path)).nil? }.sort{ |a,b| path_to_timestamp(a) <=> path_to_timestamp(b) }.collect{ |path| { File.basename(path) => File.basename(File.dirname(path)) } })
  to_publish.each_with_index do |(record_id, formats), index|
    BigBlueButtonAwsRecorder.logger.info "Processing #{index + 1} of #{to_publish.size}"
    $publisher.publish(record_id, published_dir, s3_bucket, formats)
  end
  to_unpublish = collect_values(Dir.glob("#{unpublished_dir}/*/*").reject{ |path| /\w+-\d+/.match(File.basename(path)).nil? }.sort{ |a,b| path_to_timestamp(a) <=> path_to_timestamp(b) }.collect{ |path| { File.basename(path) => File.basename(File.dirname(path)) } })
  to_unpublish.each_with_index do |(record_id, formats), index|
    BigBlueButtonAwsRecorder.logger.info "Processing #{index + 1} of #{to_unpublish.size}"
    $publisher.unpublish(record_id, unpublished_dir, s3_bucket, formats)
  end
end

if $cmd == 'watch'
  RECORDINGS_CHANNEL = "bigbluebutton:from-rap"
  $redis_pubsub = Redis.new(:host => redis_host, :port => redis_port)
  $redis_publisher = Redis.new(:host => redis_host, :port => redis_port)
  BigBlueButtonAwsRecorder.logger.info "Subscribing to bigbluebutton:from-rap"
  queued_events = {}
  $redis_pubsub.subscribe(RECORDINGS_CHANNEL) do |on|
    on.message do |channel, msg|
      BigBlueButtonAwsRecorder.logger.info "Received a message: #{msg}"

      begin
        data = JSON.parse(msg)
        type = data['header']['name']
        case type
        when "publish_ended"
          success = data['payload']['success']
          record_id = data['payload']['meeting_id']
          format = data['payload']['workflow']
          if success
            link = data['payload']['playback']['link']
            modified_link = $publisher.get_modified_link(link)
            if link == modified_link
              BigBlueButtonAwsRecorder.logger.info "Published back to redis for record_id #{record_id}, format #{format}"
            else
              formats = Dir.glob("/usr/local/bigbluebutton/core/scripts/publish/*.rb").map{ |file| File.basename(file, ".rb") }
              published_formats = Dir.glob("/var/bigbluebutton/recording/status/published/#{record_id}-*.done").map{ |file| File.basename(file, ".done").gsub(/^\w+-\d+-/, "") }
              if (formats - published_formats).empty?
                BigBlueButtonAwsRecorder.logger.info "Complete set of formats published for record_id #{record_id}"
                published_formats.each do |format|
                  $publisher.publish(record_id, published_dir, s3_bucket, [ format ])
                  if ! queued_events[record_id].nil? and ! queued_events[record_id][format].nil?
                    $redis_publisher.publish RECORDINGS_CHANNEL, queued_events[record_id][format].to_json
                  end
                end
                queued_events.delete(record_id)
                BigBlueButtonAwsRecorder.logger.debug "Complete queued events:\n#{PP.pp(queued_events, "")}"
              else
                data['payload']['playback']['link'] = modified_link
                obj = {
                  format => data
                }
                queued_events[record_id] = {} if queued_events[record_id].nil?
                queued_events[record_id].merge!(obj)
                BigBlueButtonAwsRecorder.logger.info "Waiting for the complete set of formats to publish #{record_id}, just published format #{format}"
                BigBlueButtonAwsRecorder.logger.debug "Complete queued events:\n#{PP.pp(queued_events, "")}"
              end
            end
          else
            BigBlueButtonAwsRecorder.logger.info "Regular publish failed for record_id #{record_id}, format #{format}"
          end
        when "published"
          record_id = data['payload']['meeting_id']
          $publisher.publish(record_id, published_dir, s3_bucket)
        when "unpublished"
          record_id = data['payload']['meeting_id']
          $publisher.unpublish(record_id, unpublished_dir, s3_bucket)
        when "deleted"
          record_id = data['payload']['meeting_id']
          $publisher.delete(record_id, published_dir, s3_bucket)
        end
      rescue Exception => e
        BigBlueButtonAwsRecorder.logger.error "Something went wrong: #{$!}"
      end
    end
  end
end
