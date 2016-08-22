#!/usr/bin/env ruby
# Author: Maksim Podlesnyi <mpodlesnyi@smartling.com>
require 'aws-sdk'
require 'optparse'
require 'logger'
require 'faraday'
require 'json'


class ElasticsearchWatch
  HEALTH_METRICS = [
    'number_of_nodes',
    'number_of_data_nodes',
    'active_primary_shards',
    'active_shards',
    'relocating_shards',
    'initializing_shards',
    'unassigned_shards',
    'delayed_unassigned_shards',
    'number_of_pending_tasks',
    'number_of_in_flight_fetch',
  ]
  def initialize(url, region, namespace, instance=nil)
    @cloudwatch = Aws::CloudWatch::Client.new(:region=>region)
    @connection = Faraday.new
    @es_url = url
    @namespace = namespace
    @instance = instance
  end

  def health
    res = @connection.get("#{@es_url}/_cluster/health")
    j = JSON.parse res.body
    if j.has_key?('error')
      raise "#{j['error']}\n"
    end
    health_state = j['status']
    cluster_name = j['cluster_name']
    if health_state == 'green'
      health_state = 0
    elsif health_state == 'yellow'
      health_state = 1
    elsif health_state == 'red'
      health_state = 2
    else
      health_state = 255
    end
    put_metric_data('status', health_state, cluster_name)
    HEALTH_METRICS.each do |metric|
      put_metric_data(metric, j[metric], cluster_name)
    end
  end

  def put_metric_data(metric, value, cluster, unit='None')
    # unit accepts:
    # Seconds,
    # Microseconds,
    # Milliseconds,
    # Bytes,
    # Kilobytes,
    # Megabytes,
    # Gigabytes,
    # Terabytes,
    # Bits,
    # Kilobits,
    # Megabits,
    # Gigabits,
    # Terabits,
    # Percent,
    # Count,
    # Bytes/Second,
    # Kilobytes/Second,
    # Megabytes/Second,
    # Gigabytes/Second,
    # Terabytes/Second,
    # Bits/Second,
    # Kilobits/Second,
    # Megabits/Second,
    # Gigabits/Second,
    # Terabits/Second,
    # Count/Second,
    # None
    dimensions = []

    if @instance
      dimensions << { :name => 'Instance', :value => @instance }
    end
    dimensions << { :name => 'ElasticsearchCluster', :value => cluster }

    metric_data = {
          metric_name: metric,
          dimensions: dimensions,
          timestamp: Time.now,
          value: value,
          unit: unit,
        }

    return @cloudwatch.put_metric_data({
      namespace: @namespace,
      metric_data: [metric_data],
    })
  end
end

class MyOptparse

  def self.parse(args)
    options = OpenStruct.new
    options.logfile   = false
    options.verbose   = false
    options.region    = 'us-west-1'
    options.url       = 'http://localhost:9200'
    options.namespace = 'Custom/ElasticsearchCluster'
    options.instance  = nil

    opt_parser = OptionParser.new do |opts|
      banner = [
        $0 + " -i i-73b28fc7",
        $0 + " -l log.log",
      ]
      opts.banner = "Examples:\n\t" + banner.join("\n\t")

      opts.separator ""

      opts.on('-i', '--instance INSTANCE',
              'Instance name or id') do |instance|
          options.instance = instance
      end

      opts.on('-r', '--region AWS_REGION',
              "AWS region. Default is #{options.region}") do |region|
          options.region = region
      end

      opts.on('-u', '--url ELASTICSEARCH_URL',
              "URL of ES HTTP API. Default is #{options.url}") do |url|
          options.url = url
      end

      opts.on('-n', '--namespace NAMESPACE',
              "AWS CloudWatch metricas namespace. Default is #{options.namespace}") do |namespace|
          options.namespace = namespace
      end

      opts.on('-l', '--logfile FILE',
              'Log file. By default will put all messages on stdout.') do |logfile|
          options.logfile = logfile
      end

      opts.on("-v", "--[no-]verbose", "Run verbosely. Print in stderr") do |v|
        options.verbose = v
      end

      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end
      opt_parser.parse!(args)
      options
      rescue OptionParser::ParseError
        $stderr.print "Error: " + $!.to_s + "\n"
        puts opt_parser
        exit(-1)
  end
end

if __FILE__ == $0
  begin
    options  = MyOptparse.parse(ARGV)
    $logger = Logger.new(options.logfile ? option.logfile : STDOUT)
    if options.debug
      $logger.level = Logger::DEBUG
    else
      $logger.level = Logger::INFO
    end
    if !options.logfile
      $logger.formatter = proc do |severity, datetime, progname, msg|
         "#{msg}\n"
      end
    end
    es_cw = ElasticsearchWatch.new(options.url, options.region, options.namespace, options.instance)
    es_cw.health()
  rescue Exception => e
    if defined?($logger) == 'global-variable'
      $logger.error e.message
    else
      $stderr.puts e.message
    end
    exit(1)
  end
end
