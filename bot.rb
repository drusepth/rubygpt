require "zircon"
require "openai" # gem "ruby-openai"
require 'pry'

NICK    = 'CB'
CHANNEL = '#fj'

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

    should_respond = rand(1..100) == 1 || (message.body && message.body.start_with?("#{NICK}:"))
    if should_respond
      # Use ChatGPT API
      system_message = {
        "role": "system", 
        "content": "You are in a group chat with multiple hyperintelligent users. DO NOT MENTION THAT YOU ARE A LANGUAGE MODEL. Don't say your name, which is #{NICK}, or refer any user by their name. You can be witty, rude, clever, mean, snarky, insulting, interesting, or any combination of the above, but don't be boring. Do not continue on from any previous messages. Start your response as a new message. Only generate one message a time. Only speak on behalf of yourself, not any users."
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