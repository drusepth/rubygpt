require "zircon"
require "openai" # gem "ruby-openai"
require 'pry'

NICK    = 'gaben'
CHANNEL = '#gaming'

recent_chat_history = []

client = Zircon.new(
  :server   => "irc.wobscale.website",
  :port     => "6667",
  :channel  => CHANNEL,
  :username => NICK,
  :password => "optional password",
)
openai = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))

# client.on_privmsg do |message|
#   client.privmsg "#chatroid", ":zircon!"
# end

client.on_message do |message|
  # puts "*** `on_message` responds with all received message ***"
  # puts message.from
  # puts message.to
  # puts message.type
  # puts message.body

  if message.type == 'privmsg' && message.to == CHANNEL
    puts "<#{message.from}> #{message.body}"
    recent_chat_history << "#{message.body}"

    # Limit chat history to 6 most recent messages
    recent_chat_history = recent_chat_history.last(6)
    formatted_chat_history = recent_chat_history.map do |message|
      { role: 'user', content: message }
    end

    should_respond = rand(1..100) == 1 || message.body.start_with?("#{NICK}: ")
    if should_respond
      # Use ChatGPT API
      system_message = {
        "role": "system", 
        "content": "You are in a group chat with multiple Dota 2 superfans. DO NOT MENTION THAT YOU ARE A LANGUAGE MODEL. Don't say your name, which is #{NICK}, or refer any user by their name. You are extremely knowledgable about Dota 2, its mechanics, its playable heroes, its items, and the current meta. You are extremely open to trying new metas and new playstyles on heroes, and may suggest things that aren't normally kosher. You recommend playing supports as carries and carries as supports. Having fun is more important than winning. Do not continue on from any previous messages. Start your response as a new message. Only generate one message a time. Only speak on behalf of yourself, not any users. Keep your response short enough to fit in an IRC message."
      }
      puts "Chat history:"
      puts [system_message, formatted_chat_history].flatten
      response = openai.chat(
        parameters: {
          model:       "gpt-3.5-turbo",
          messages:    [system_message, formatted_chat_history].flatten,
          temperature: 0.7,
        })
      retort = response.dig("choices", 0, "message", "content")
      puts "Message to respond with:"
      puts retort

      # Send response
      client.privmsg CHANNEL, ":#{message.from}: #{retort}"
    end
  end
end

client.on_notice do |message|
  client.join CHANNEL
end

puts "Starting bot..."
client.run!
puts "Bot is dead!"