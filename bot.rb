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

def split_long_message_into_irc_chunks(message, max_chunk_length=420)
  return "" if message.nil?

  chunks = []
  current_chunk = ""

  message.split(/\n/).each_with_index do |line, line_index|
    # Send any standalone lines shorter than max_chunk_length as a line of their own
    if line.length <= max_chunk_length
      chunks << line
      next
    end

    # If this line is longer than the max_chunk_length, we need to send it over multiple lines.
    line.split(/\s+/).each_with_index do |word, word_index|
      # If we have room in this chunk for the next word, add it.
      if current_chunk.size + word.size + 1 <= max_chunk_length
        current_chunk += ' ' unless current_chunk.empty? || current_chunk.end_with?("\n") || word_index.zero?
        current_chunk += word

      # If we DON'T have room in this chunk for the next word, end the chunk and start a new one.
      else
        chunks << current_chunk
        current_chunk = word
      end
    end
  end

  chunks << current_chunk unless current_chunk.empty?
  chunks
end

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
        "content": "You are in a group chat with multiple senior programmers. DO NOT MENTION THAT YOU ARE A LANGUAGE MODEL. Don't say your name, which is #{NICK}, or refer any user by their name. You have expert knowledge of many programming languages and frameworks, including Go, Ruby, Python, C, Javascript, and others. Please answer with detailed programming help, using documentation and experience. Do not continue on from any previous messages. Start your response as a new message. Only generate one message a time. Only speak on behalf of yourself, not any user."
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
      retort_chunks = split_long_message_into_irc_chunks(retort)

      retort_chunks.each_with_index do |chunk, i|
        chunk = "#{message.from}: #{chunk}" if i == 0
        client.privmsg CHANNEL, ":#{chunk}"

        # Add a small delay between messages to make sure they all arrive in order :)
        sleep 0.5
      end
    end
  end
end

client.on_notice do |message|
  client.join CHANNEL
end

puts "Starting bot..."
client.run!
puts "Bot is dead!"
