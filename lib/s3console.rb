# encoding: UTF-8

# require 's3console/version'
#
# module S3console
#   # Your code goes here...
# end

# Temporary code goes here...

require 'aws-sdk'
require 'logger'

require_relative 's3console/utils'

class S3Console
  S3_PATH_PREFIX = 's3://'

  attr_reader :client,
              :current_path,
              :is_truncated, :next_marker

  attr_accessor :max_keys

  def initialize(logger: nil)
    @client = Aws::S3::Client.new(region: 'us-east-1')
    @current_path = S3_PATH_PREFIX
    @logger = logger || Logger.new('/tmp/s3_console.log')
    @max_keys = 100
  end

  def ls
    return list_buckets.keys unless current_bucket
    objects = list_objects
    return [] unless objects
    directories = objects.common_prefixes.collect(&:prefix).map { |d| d.sub(/^#{Regexp.quote(objects.prefix)}/, '') }
    files = objects.contents.collect(&:key).map { |f| f.sub(/^#{Regexp.quote(objects.prefix)}/, '') }

    directories + files
  end

  def cd(path = nil)
    @current_path = if path.nil? || path == '/'
                      S3_PATH_PREFIX
                    elsif path == '.'
                      @current_path
                    elsif path == '..'
                      unless root?
                        path = File.split(@current_path).first
                        path == 's3:' ? S3_PATH_PREFIX : path
                      end
                    else
                      File.join @current_path, path, '/'
                    end

    @is_truncated = false
    @next_marker = nil
  end

  def root?
    @current_path == S3_PATH_PREFIX
  end

  private

  def current_bucket
    @current_path.scan(%r|#{S3_PATH_PREFIX}([^/]+)|).flatten.first
  end

  def current_prefix
    @current_path.scan(%r|#{S3_PATH_PREFIX}[^/]+/(.+)|).flatten.first
  end

  def list_buckets
    @buckets ||= @client.list_buckets
                   .buckets
                   .map { |b| [b.name, @client.get_bucket_location(bucket: b.name).location_constraint] }
                   .to_h
  end

  def list_objects
    @logger.info "bucket: #{current_bucket}, prefix: #{current_prefix}"
    return unless current_bucket
    bucket_region = list_buckets[current_bucket]
    c = bucket_region.nil? || bucket_region.empty? ? client : Aws::S3::Client.new(region: bucket_region)
    begin
      objects = c.list_objects(bucket: current_bucket,
                               delimiter: '/',
                               prefix: current_prefix,
                               max_keys: @max_keys,
                               marker: @next_marker)
      @is_truncated = objects.is_truncated
      @next_marker = objects.next_marker
      objects
    rescue Aws::S3::Errors::ServiceError => error
      @logger.error error.message
      nil
    end
  end
end


$s3_console = S3Console.new

def print_files(files)
  return if files.nil? || files.empty?
  max_len = files.map(&:size).max
  slice_size = 80/max_len > 0 ? 80/max_len : 1
  STDOUT.puts files.sort.map { |f| sprintf("%-#{max_len}s", f) }.each_slice(slice_size).map { |a| a.join("\t") }.join("\n")
end

def ls_files(files = nil)
  print_files files || $s3_console.ls
  loop do
    break unless $s3_console.is_truncated

    STDOUT.puts ' -*- press space to load more, press q to quit -*- '
    while c = STDIN.getch
      case c
        when ' '
          break
        when 'q'
          $s3_console.cd '.'
          return
      end
    end

    print_files $s3_console.ls
  end
end

while l = Utils::Input.gets
  puts l
end

#print_files $s3_console.ls
#while line = gets_with_prompt
#  case line.strip
#    when /^ls$/
#      ls_files
#    when /^cd(\s+(.+))?/
#      if $2
#        $s3_console.cd $2
#        files = $s3_console.ls
#
#        if files.nil? || files.empty?
#          STDERR.puts "no such file or directory: #{$2}"
#          $s3_console.cd '..'
#        end
#      else
#        $s3_console.cd
#      end
#    when /exit/
#      break
#    else
#      STDERR.puts "command not found: #{line}"
#  end
#
#  STDOUT.puts
#end
