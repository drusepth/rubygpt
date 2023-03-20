require "zircon"
require "openai" # gem "ruby-openai"
require "yaml"
require "pry"

# Council meeting spot
SERVER  = 'irc.wobscale.website'
PORT    = 6667
CHANNEL = '#council'

MESSAGE_CONTEXT_WINDOW_LENGTH = 1

OPENAI = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
message_mutex = Mutex.new

# Load and set up the council
council_config  = YAML.load_file("council.yml")
COUNCIL_MEMBERS = council_config["council_members"]
COUNCIL_MEMBERS.each do |member|
  member['system_prompt'] = member['system_prompt'].split("\n").join(" ").gsub(/\s+/, ' ').strip
end

def split_long_message_into_irc_chunks(message, max_chunk_length=420)
  return ""        if message.nil?
  return [message] if message.length <= max_chunk_length

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

def create_council_member(name, system_prompt, speaking_mutex)
  recent_chat_history = []

  client = Zircon.new(server: SERVER, port: PORT, channel: CHANNEL, username: name)
  client.on_message do |message|
    message_from_council = COUNCIL_MEMBERS.map { |m| m['name'] }.include?(message.from)

    if message.type == 'privmsg' && message.to == CHANNEL && !message_from_council
      # Limit chat history to N most recent messages
      recent_chat_history << { role: 'user', content: message.body }
      recent_chat_history = recent_chat_history.last(MESSAGE_CONTEXT_WINDOW_LENGTH)

      # If the message is directed to any particular council member, only respond if you
      # are that council member. If the message isn't directed, always respond.
      message_directed_to = COUNCIL_MEMBERS.detect { |member| message.body.start_with?(member['name']) }
      should_respond      = message_directed_to.nil? || message_directed_to['name'] == name

      # puts "Message directed to... #{message_directed_to}"
      # puts "Should respond? #{should_respond}"
  
      if should_respond
        system_message = { role: "system", content: system_prompt }

        response = OPENAI.chat(
          parameters: {
            model:       "gpt-3.5-turbo",
            messages:    [system_message, recent_chat_history].flatten,
            temperature: 0.7,
          })
        # puts "Recent chat history:"
        # puts [system_message, recent_chat_history].flatten
        retort = response.dig("choices", 0, "message", "content")
        puts retort

        # We use a mutex to make sure each councilperson respectfully takes their turn speaking,
        # especially when sending multiple messages in a row. We wouldn't want everyone talking
        # over each other!
        retort_chunks = split_long_message_into_irc_chunks(retort)
        speaking_mutex.synchronize do
          retort_chunks.each_with_index do |chunk, i|
            if !chunk.blank?
              chunk = "#{message.from}: #{chunk}" if i == 0
              client.privmsg CHANNEL, ":#{chunk}"

              # Add a small delay between messages to make sure they all arrive in order :)
              sleep 0.5
            end
          end

          # Also add a small delay between speakers to signify the end of their turn
          sleep 3
        end
      end
    end
  end

  # Wait until we've got a notice from the server before joining any channel(s)
  client.on_notice do |message|
    client.join CHANNEL
  end

  client
end

# Create and run the bots in separate threads
puts "Adding #{COUNCIL_MEMBERS.length} council members..."
bot_threads = COUNCIL_MEMBERS.map do |member|
  puts "\t#{member['name']}..."
  Thread.new do
    bot = create_council_member(member['name'], member['system_prompt'], message_mutex)
    bot.run!
  end
end

# Wait for all threads to finish
bot_threads.each(&:join)
puts "Bot(s) are dead!"