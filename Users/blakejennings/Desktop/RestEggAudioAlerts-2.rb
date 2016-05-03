# Rest Egg Noise Detection and Alert Script
# 
# This program is free to use and edit. You may distribute it under the terms of
# the GNU General Public License as published by the Free Software
# Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but
# without any warranty. See the GNU General Public License for more details.
#
#

# get 'libraries'
require 'getoptlong'
require 'net/https'
require 'optparse'
require 'net/smtp'
require 'logger'
require 'date'

# parameter setup
HW_DETECTION_CMD = "cat /proc/asound/cards" # finds and names sound cards, 
# ^and their status
SAMPLE_DURATION = 10 	# seconds for our running test
FORMAT = 'S16_LE'   	# the output format of our C-Media USB sound card
THRESHOLD = 0.20    	# as oposed to a max of 1; .2 is 30db, our target

# files
RECORD_FILENAME='/tmp/noise.wav' 	# name the recording file for SoX analysis
LOG_FILE='/var/log/noise_detector.log'	# name the placeholder file
PID_FILE='/etc/noised/noised.pid'	# process ID, for the kernel

# logger adjusts warning level
logger = Logger.new(LOG_FILE)
logger.level = Logger::DEBUG

# start of recording
puts("Audio sensing started on #{DateTime.now.strftime('%d/%m/%Y %H:%M:%S')}")

# check for needed packages
def self.check_required()
  if !File.exists?('/usr/bin/arecord')
    warn "arecord not found at /usr/bin/arecord. Please install package alsa-utils"
    exit 1
  end
  if !File.exists?('/usr/bin/sox')
    warn "SoX not found at /usr/bin/sox. Please install package sox"
    exit 1
  end
  if !File.exists?('/proc/asound/cards')
    warn "/proc/asound/cards not found"
    exit 1
  end
  
end

# Parsing script parameters
options = {}
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: RestEggAudioAlerts.rb -m ID [options]"

  opts.on("-m", "--microphone SOUND_CARD_ID", "REQUIRED: Set microphone id") do |m|
    options[:microphone] = m
  end
  opts.on("-s", "--sample SECONDS", "Sample duration") do |s|
    options[:sample] = s
  end
  opts.on("-n", "--threshold NOISE_THRESHOLD", "Set Activation noise Threshold. EX. 0.1") do |n|
    options[:threshold] = n
  end
  opts.on("-e", "--email DEST_EMAIL", "Alert destination email") do |e|
    options[:email] = e
  end
  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end
  opts.on("-d", "--detect", "Detect your sound cards") do |d|
    options[:detection] = d
  end
  opts.on("-t", "--test SOUND_CARD_ID", "Test soundcard with the given id") do |t|
    options[:test] = t
  end
  opts.on("-k", "--kill", "Terminating background script") do |k|
    options[:kill] = k
  end
end.parse!

if options[:kill]
  logger.info("Terminating script");
  logger.debug("Looking for pid file in #{PID_FILE}")
  begin
    pidfile = File.open(PID_FILE, "r")
    storedpid = pidfile.read
    Process.kill("TERM", Integer(storedpid))
  rescue Exception => e
    logger.error("Cannot read pid file: " + e.message)
    exit 1
  end
  exit 0
end

if options[:detection]
    puts "Detecting your soundcard..."
    puts `#{HW_DETECTION_CMD}`
    exit 0
end

# Check the needed binaries- user functions
check_required()

if options[:sample]
    SAMPLE_DURATION = options[:sample]
end

if options[:threshold]
    THRESHOLD = options[:threshold].to_f
end

if options[:test]
    puts "Testing Rest Egg soundcard"
    puts `/usr/bin/arecord -D plughw:#{options[:test]},0 -d #{SAMPLE_DURATION} -f #{FORMAT} 2>/dev/null | /usr/bin/sox -t .wav - -n stat 2>&1`
    exit 0
end

optparse.parse!

#Now raise an exception if we have not found a host option
raise OptionParser::MissingArgument if options[:microphone].nil?
raise OptionParser::MissingArgument if options[:email].nil?

if options[:verbose]
   logger.debug("Script parameters configurations:")
   logger.debug("SoundCard ID: #{options[:microphone]}")
   logger.debug("Sample Duration: #{SAMPLE_DURATION}")
   logger.debug("Output Format: #{FORMAT}")
   logger.debug("Noise Threshold: #{THRESHOLD}")
   logger.debug("Record filename (overwritten): #{RECORD_FILENAME}")
   logger.debug("Destination email: #{options[:email]}")
end

#Starting script part
pid = fork do		# pid file support; pid files contains process id info
  stop_process = false
  Signal.trap("USR1") do
    logger.debug("Listening")
  end
  Signal.trap("TERM") do
    logger.info("Stopping")
    File.delete(PID_FILE)
    stop_process = true 
  end

  loop do		# in case of termination
    if (stop_process)
	logger.info("Rest Egg stopped at #{DateTime.now.strftime('%d/%m/%Y %H:%M:%S')}")	
	break
    end

# use function arecord to record a wav file with the customized parameters
    rec_out = `/usr/bin/arecord -D plughw:#{options[:microphone]},0 -d #{SAMPLE_DURATION} -f #{FORMAT} -t wav #{RECORD_FILENAME} 2>/dev/null`

# use command line utility SoX to test the created .wav file
    out = `/usr/bin/sox -t .wav #{RECORD_FILENAME} -n stat 2>&1`
# 
    out.match(/Maximum amplitude:\s+(.*)/m)
    amplitude = $1.to_f
# logger receives extra details on the amplitute
    logger.debug("Detected amplitude: #{amplitude}") if options[:verbose]

# if this amplitude breaches WHO standards, alert
    if amplitude > THRESHOLD     
	logger.info("Excessive Noise")
	puts("Excessive Noise detected")

####Pushover Connection####

# create a post request with a JSON object, sending to API endpoint in the url (Pushover)
# API -- application program interface- rules for the application.
  url = URI.parse("https://api.pushover.net/1/messages.json")
req = Net::HTTP::Post.new(url.path)
req.set_form_data({

# this JSON object contains the token, user, and message information
  :token => "aFvczTDoiCaS5khE3TRfYLxsreYi2j",
  :user => "uWrJd9EFpm7VVe3uaK2TawYKPTx3WR",
  :message => "Excessive noise detected.",
})
res = Net::HTTP.new(url.host, url.port)

# use SSL; security is often required
res.use_ssl = true
res.verify_mode = OpenSSL::SSL::VERIFY_PEER
res.start {|http| http.request(req) }

####

# pause for noise problem to be adressed
sleep(10) 

# logger entry for no sound
    else
      logger.debug("No sound detected...")
    end
end
end

Process.detach(pid)
logger.debug("Started... (#{pid})")
File.open(PID_FILE, "w") { |file| file.write(pid) }