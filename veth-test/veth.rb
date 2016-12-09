#!/usr/bin/env ruby

COMPOSE_PREFIX='vethveth2'

class String
  def colorize(color_code) "\e[#{color_code}m#{self}\e[0m" end
  def bold; colorize(1) end
  def red; colorize(31) end
  def green; colorize(32) end
  def yellow; colorize(33) end
  def cyan; colorize(36) end
end

require 'optparse'

$options = {:range => nil}

parser = OptionParser.new do|opts|
	opts.banner = "Usage: years.rb [options]"
	opts.on('-r', '--range range', 'Docker host range: 18,23') do |range|
    abort "Invalid range" unless range.match(/\d+,\d+/)
		$options[:range] = range;
	end

	opts.on('-h', '--help', 'Displays Help') do
		puts opts
		exit
	end
end

parser.parse!

def number_to_host(i)
  "bld-docker-#{i.to_s.rjust(2, '0')}"
end

def test_veth(dhost_n_1, dhost_n_2)
  dhost_1 = number_to_host dhost_n_1
  dhost_2 = number_to_host dhost_n_2

  puts "#{dhost_1} #{dhost_2}".cyan

  ENV['DOCKER_HOST'] = 'tcp://bld-swarm-01:2375'
  ENV['DHOST_1'] = dhost_1
  ENV['DHOST_2'] = dhost_2

  cmd = "docker-compose -p #{COMPOSE_PREFIX}_#{dhost_n_1} -f veth.yml up --force-recreate 2>&1"
  puts "Running docker command: #{"DHOST_1=#{dhost_1} DHOST_2=#{dhost_2} #{cmd}".yellow}"
  compose_out = `#{cmd}`
  if compose_out.match('could not add veth')
    image_line = `docker ps -a | grep #{COMPOSE_PREFIX} | grep 'Created' 2>&1`
    match = image_line.scan(/bld-docker-\d\d/)
    if match.nil?
      puts "got no match for line: #{image_line}".red
      exit
    end

    puts "Veth error on #{match[0]}".red if match[0]
    puts "Veth error on #{match[1]}".red if match[1]
  elsif compose_out.match(/network \w+ not found/)
    puts "Error: network not found".red
  elsif compose_out.match(/getsockopt: no route to host/)
    puts "getsockopt: no route to host".red
  elsif compose_out.match(/ValueError: No JSON object could be decoded/)
    puts "ValueError: No JSON object could be decoded".red
  elsif $? != 0
    puts "Got some error.  Compose output:"
    puts compose_out

  else

    # we gotta check for running state of those containers
    # `docker ps | grep #{COMPOSE_PREFIX} | Running`

    puts "No veth error".green

  end

  `docker-compose -p #{COMPOSE_PREFIX} down 2>&1`
end

def get_host_range
  if $options[:range].nil?
    (4...26).to_a.concat((30...32).to_a)
  else
    range_start, range_end = $options[:range].split(',')
    puts "Using range (#{range_start}...#{range_end})...".yellow
    (range_start.to_i...range_end.to_i)
  end
end

get_host_range.map do |i|
  test_veth i, i+1
end

puts "Checked all hosts".green

puts "Removing all containers...".yellow
puts `docker ps -a | grep #{COMPOSE_PREFIX} | awk '{print $1}' | xargs docker rm -fv`

puts "Removing all networks...".yellow
puts `docker network ls | grep #{COMPOSE_PREFIX} | awk '{print $1}' | xargs docker network rm`