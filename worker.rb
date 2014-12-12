require 'mechanize'
require 'redis'
require 'twitter'

$stdout.sync = true

@agent = Mechanize.new
@interval = ENV['INTERVAL'].to_i.zero? ? 60 : ENV['INTERVAL'].to_i
@redis = Redis.new(url: ENV['REDISTOGO_URL'])
@twitter = Twitter::REST::Client.new(
  consumer_key: ENV['TWITTER_CONSUMER_KEY'],
  consumer_secret: ENV['TWITTER_CONSUMER_SECRET'],
  access_token: ENV['TWITTER_ACCESS_TOKEN'],
  access_token_secret: ENV['TWITTER_ACCESS_TOKEN_SECRET']
)

def run
  login(ENV['SEGA_ID'], ENV['SEGA_ID_PASSWORD'])
  new_log = take_new_log(log, last)
  post_to_twitter(new_log)
end

def login(sega_id, password)
  form = @agent.get('https://coj-agentlabo.com/login').form
  form.sega_id = sega_id
  form.password = password
  form.action = '/login'
  select_aime = form.submit
  select_aime.forms.last.submit
end

def log
  page = @agent.get('https://coj-agentlabo.com/friends')
  log, date = [], '00/00'
  page.parser.css('#friends_log_main_contents').children.each do |element|
    case element.name
    when 'dt'
      date = element.text
    when 'dd'
      log << "#{date} #{element.text}"
    end
  end
  log
end

def last
  @redis['last_log']
end

def take_new_log(log, last)
  log.take_while do |line|
    line != last
  end
end

def post_to_twitter(log)
  log = log.reverse
  text = []
  log.each do |line|
    update(text) && text = [] if text.map(&:size).inject(0, &:+) + text.size - 1 + line.size > 140
    text << line
  end
  update(text)
end

def update(text)
  return if text.empty?
  puts(status = text.reverse.join("\n"))
  @twitter.update(status)
  @redis['last_log'] = text.last
end

loop do
  Thread.new do
    begin
      run
    rescue => e
      puts e.message
    end
  end

  sleep(@interval)
end
