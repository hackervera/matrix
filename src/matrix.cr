require "./matrix/*"
require "http/client"
require "json"
require "logger"
require "secure_random"
require "intuit"
require "readline"
require "ncurses"
require "big_int"

module Matrix
  USER      = ENV["MATRIX_USER"] ||= ""
  PASS      = ENV["MATRIX_PASS"] ||= ""
  MATRIX_HS = ENV["MATRIX_HS"] ||= "https://matrix.org"

  class Client
    getter :connection_info, :user, :matrix_host, :logger
    @matrix_host : String

    def send_devices(user_ids, room_ids)
      # @logger.debug room_ids
      messages = Hash(String, Hash(String, Hash(String, Array(String) | String))).new
      user_ids.each do |user_id|
        messages[user_id] = {"*" => {"device_id" => @connection_info.device_id, "rooms" => room_ids}}
      end
      # @logger.debug messages
      response = HTTP::Client.put(url: "#{MATRIX_HS}/_matrix/client/unstable/sendToDevice/m.new_device/#{SecureRandom.hex}?access_token=#{@connection_info.access_token}", body: {messages: messages}.to_json)
      # @logger.debug response.inspect
    end

    def initialize(@user : String = USER, @pass : String = PASS)
      @logger = Logger.new(STDIN)
      @matrix_host = MATRIX_HS.gsub(/.*\/\//, "")
      response = HTTP::Client.post(url: "#{MATRIX_HS}/_matrix/client/r0/login", body: {type: "m.login.password", user: @user, password: @pass}.to_json)
      @connection_info = ConnectionInfo.from_json(response.body)
      @account = Intuit::Account.new(device_id: @connection_info.device_id, user_id: @connection_info.user_id)
      @account.create
      @account.generate_one_time_keys(50)
      @sessions = Hash(String, Intuit::InboundGroupSession).new
      NCurses.init
      NCurses.raw
      NCurses.no_echo
      @window = NCurses::Window.new(40, 80)
      LibNCurses.scrollok(@window, true)
      LibNCurses.idlok(@window, true)
      @history = Hash(String, Array(String)).new
      @channel_selector = 0
      @offset = 0
    end

    def device_list(user_ids)
      device_keys = Hash(String, Array(Nil)).new
      user_ids.each do |user_id|
        device_keys[user_id] = [] of Nil
      end
      # @logger.debug device_keys
      response = HTTP::Client.post(url: "#{MATRIX_HS}/_matrix/client/unstable/keys/query?access_token=#{@connection_info.access_token}", body: {"device_keys" => device_keys}.to_json)
    end

    def claim_key(user_id, device_id)
      response = HTTP::Client.post(url: "#{MATRIX_HS}/_matrix/client/unstable/keys/claim?access_token=#{@connection_info.access_token}", body: {"one_time_keys" => {user_id => {device_id => "signed_curve25519"}}}.to_json)
    end

    def upload_keys
      response = HTTP::Client.post(url: "#{MATRIX_HS}/_matrix/client/unstable/keys/upload?access_token=#{@connection_info.access_token}", body: @account.to_json)
    end

    def create_session(event)
      # @logger.debug event
      cipher_key = event.content["ciphertext"].as_h.keys.first
      cipher_body = event.content["ciphertext"][cipher_key]["body"].to_s
      cipher_copy1 = String.new(cipher_body.to_slice)
      cipher_copy2 = String.new(cipher_body.to_slice)
      session = Intuit::Session.new
      session.create_inbound_from(@account, event.content["sender_key"].to_s, cipher_copy1)
      decrypted = session.decrypt(0, cipher_copy2)
      session_data = JSON.parse(decrypted)
      # @logger.debug decrypted
      inbound_session = Intuit::InboundGroupSession.new(session_data["content"]["session_key"].to_s, session_data["content"]["chain_index"].as_i)
      @sessions[session_data["content"]["room_id"].to_s] = inbound_session
    end

    def sync(timestamp = "")
      # @history["system"] ||= Array(String).new
      # @history["system"] << "Sync"
      read_loop(:loop) unless @initiated
      @initiated ||= true
      # output "Syncing"
      since = timestamp.empty? ? timestamp : "&since=#{timestamp}"
      # output since
      response = HTTP::Client.get(url: "#{MATRIX_HS}/_matrix/client/r0/sync?access_token=#{@connection_info.access_token}#{since}")
      # @window.refresh
      sync_data = Sync.from_json(response.body)
      sync_data.to_device.events.each do |event|
        if event.type == "m.room.encrypted"
          create_session(event)
        end
      end
      sync_data.rooms.join.each do |room_id, joined_room|
        joined_room.timeline.events.each do |event|
          if event.type == "m.room.encrypted" && @sessions[room_id]?
            # output room_id
            # output event.content
            # output event.type
            decrypted = @sessions[room_id].decrypt(event.content["ciphertext"].to_s)
            # output decrypted
            decrypted_data = JSON.parse(decrypted)
            body = decrypted_data["content"]["body"]
            @history[room_id] ||= Array(String).new
            @history[room_id] << "[#{event.sender} :  #{body} [encrypted]"
          elsif event.type == "m.room.message"
            @history[room_id] ||= Array(String).new
            @history[room_id] << "#{event.sender} #{event.content["body"].to_s}"
          end
        end
      end
      sync(sync_data.next_batch)
    end

    def show_history
      @window.clear
      history_length = 15
      # # @window.print "#{@history.join("\n")}\n"
      room_id = @history.keys[@channel_selector]
      room_messages = @history[room_id]
      if room_messages.size < history_length
        idx = 0
      else
        idx = -1 * history_length
      end
      size = (idx - BigInt.new(@offset)).abs
      @window.print "Size:#{size} Offset:#{@offset}  History:#{room_messages.size} \n"
      @window.print "#{room_id}\n"
      @window.print room_messages[idx - @offset, history_length].join("\n") unless size > room_messages.size
      # @window.print("\n\n")
      # room_messages.each do |room_message|
      #   @window.print "#{room_message}\n"
      # end
      @window.refresh
    rescue e
      @window.print e.inspect
      @window.refresh
    end

    def read_loop(state)
      spawn do
        input = NCurses::Window.new(20, 80, 40)
        # LibNCurses.scrollok(input, true)
        loop do
          sleep 0.05
          show_history
          input.on_input(timeout: true) do |char, modifier|
            if modifier == :alt
              abort :bye
            end
            next if char == :nothing
            input.print modifier.to_s
            case char
            when :up
              @offset += 1
              # input.print "up"
            when :down
              @offset -= 1
              # input.print "down"
            when :right
              @channel_selector += 1
            when :left
              @channel_selector -= 1
            else
              input.print char.to_s
            end
            input.refresh
          end
        end
      end
    end

    def draw
      # state = read_loop(:loop)
      @window.print "Connecting...", [0, 0]
      @window.refresh
      sleep 3
      @window.print "Connected...", [0, 0]
      @window.refresh
      sleep 1
      puts "state is: "
    end
  end
end
