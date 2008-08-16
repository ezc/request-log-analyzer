#!/usr/bin/ruby
require 'lib/command_line/arguments'
require 'lib/rails_analyzer/log_parser'
require 'lib/rails_analyzer/summarizer'

puts "Rails log analyzer, by Willem van Bergen and Bart ten Brinke"
puts 

# Substitutes variable elements in a url (like the id field) with a fixed string (like ":id")
# This is used to aggregate simular requests.
# <tt>request</tt> The request to evaluate.
# Returns an url string.
# Raises on mailformed request.
def request_hasher(request)
  if request[:url]
    url = request[:url].downcase.split(/^http[s]?:\/\/[A-z0-9\.-]+/).last.split('?').first # only the relevant URL part
    url << '/' if url[-1] != '/'[0] && url.length > 1 # pad a trailing slash for consistency

    url.gsub!(/\/\d+-\d+-\d+/, '/:date') # Combine all (year-month-day) queries
    url.gsub!(/\/\d+-\d+/, '/:month') # Combine all date (year-month) queries
    url.gsub!(/\/\d+/, '/:id') # replace identifiers in URLs
        
    return url
  elsif request[:controller] && request[:action]
    return "#{request[:controller]}##{request[:action]}"
  else
    raise 'Cannot hash this request! ' + request.inspect
  end
end

# Print results using a ASCII table.
# <tt>summarizer</tt> The summarizer containg information to draw the table.
# <tt>field</tt> The field containing the data to be printed
# <tt>amount</tt> The length of the table (defaults to 20)
def print_table(summarizer, field, amount = 20)
  summarizer.sort_actions_by(field).reverse[0, amount.to_i].each do |a|
    if field == :count
      puts "#{a[0].ljust(50)}: %d requests" % a[1][:count]
    else
      puts "#{a[0].ljust(50)}: %10.03fs [%d requests]" % [a[1][field], a[1][:count]]
    end
  end
end

# Parse the arguments given via commandline
begin
  $arguments = CommandLine::Arguments.parse do |command_line|
    command_line.switch(:guess_database_time, :g)
    command_line.switch(:fast, :f)
    command_line.flag(:output, :alias => :o)
    command_line.flag(:amount, :alias => :c)
    command_line.required_files = 1
  end
  
rescue CommandLine::Error => e
  puts "ARGUMENT ERROR: " + e.message
  puts
  load "output/usage.rb"
  exit(0) 
end

$summarizer = RailsAnalyzer::Summarizer.new(:calculate_database => $arguments[:guess_database_time])
$summarizer.blocker_duration = 1.0

line_types = $arguments[:fast] ? [:completed] : [:started, :completed]

# Walk through al the files given via the arguments.
$arguments.files.each do |log_file|
  puts "Processing #{line_types.join(', ')} log lines from #{log_file}..."
  parser = RailsAnalyzer::LogParser.new(log_file).each(*line_types) do |request|
    $summarizer.group(request)  { |r| request_hasher(r) }
  end
end

# Select the reports to output and generate them.
output_reports = $arguments[:output].split(',') rescue [:timespan, :most_requested, :total_time, :mean_time, :total_db_time, :mean_db_time, :blockers, :hourly_spread] 

output_reports.each do |report|
  if File.exist?("output/#{report}.rb")
    load "output/#{report}.rb" 
  else
    puts "\nERROR: Output report #{report} not found!"
  end
end
