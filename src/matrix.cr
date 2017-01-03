require "./matrix/*"
require "http/client"
require "json"
require "logger"
require "secure_random"
require "intuit"

module Matrix
  USER      = ENV["MATRIX_USER"] ||= ""
  PASS      = ENV["MATRIX_PASS"] ||= ""
  MATRIX_HS = ENV["MATRIX_HS"] ||= "https://matrix.org"
  EVENTS    = Channel::Buffered(Hash(String, JSON::Type)).new

  class ConnectionInfo
    JSON.mapping(
      access_token: String,
      home_server: String,
      user_id: String,
      device_id: String
    )
  end

  class DecryptedKey
    JSON.mapping(
      algorithm: String,
      room_id: String,
      session_id: String,
      session_key: String,
      chain_index: Int32,
    )
  end

  class NewDevice
    JSON.mapping(
      rooms: Array(String),
      device_id: String
    )
  end

  class NewSession
    JSON.mapping(
      sender_key: String,
      ciphertext: JSON::Any,
      algorithm: String
    )
  end

  class Sync
    JSON.mapping(
      next_batch: String,
      presence: Presence,
      rooms: Rooms,
      account_data: AccountData,
      to_device: ToDevice
    )
  end

  class AccountData
    JSON.mapping(
      events: Array(Event)
    )
  end

  class ToDevice
    JSON.mapping(
      events: Array(Event)
    )
  end

  class Presence
    JSON.mapping(
      events: Array(Event)
    )
  end

  class Rooms
    JSON.mapping(
      invite: Hash(String, InvitedRoom),
      join: Hash(String, JoinedRoom),
      leave: Hash(String, LeftRoom)
    )
  end

  class JoinedRoom
    JSON.mapping(
      state: State,
      timeline: Timeline,
      ephemeral: Ephemeral,
      account_data: AccountData,
      unread_notifications: UnreadNotifications
    )
  end

  class Ephemeral
    JSON.mapping(
      events: Array(Event)
    )
  end

  class UnreadNotifications
    JSON.mapping(
      highlight_count: Int32 | Nil,
      notification_count: Int32 | Nil
    )
  end

  class InvitedRoom
    JSON.mapping(
      invite_state: InviteState
    )
  end

  class InviteState
    JSON.mapping(
      events: Array(Event)
    )
  end

  class LeftRoom
    JSON.mapping(
      state: State,
      timeline: Timeline)
  end

  class State
    JSON.mapping(
      events: Array(Event))
  end

  class Timeline
    JSON.mapping(
      events: Array(Event),
      limited: Bool,
      prev_batch: String)
  end

  class Event
    JSON.mapping(
      content: JSON::Any,
      origin_server_ts: Int32 | Nil,
      state_key: String | Nil,
      type: String,
      sender: String | Nil,
      unsigned: Unsigned | Nil
    )
  end

  class Unsigned
    JSON.mapping(
      age: Int32 | Nil,
      prev_content: JSON::Any | Nil,
      transaction_id: String | Nil
    )
  end

  class Client
    getter :connection_info, :user, :matrix_host, :logger
    @matrix_host : String

    def send_devices(user_ids, room_ids)
      @logger.debug room_ids
      messages = Hash(String, Hash(String, Hash(String, Array(String) | String))).new
      user_ids.each do |user_id|
        messages[user_id] = {"*" => {"device_id" => @connection_info.device_id, "rooms" => room_ids}}
      end
      @logger.debug messages
      response = HTTP::Client.put(url: "#{MATRIX_HS}/_matrix/client/unstable/sendToDevice/m.new_device/#{SecureRandom.hex}?access_token=#{@connection_info.access_token}", body: {messages: messages}.to_json)
      @logger.debug response.inspect
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
    end

    def device_list(user_ids)
      device_keys = Hash(String, Array(Nil)).new
      user_ids.each do |user_id|
        device_keys[user_id] = [] of Nil
      end
      @logger.debug device_keys
      response = HTTP::Client.post(url: "#{MATRIX_HS}/_matrix/client/unstable/keys/query?access_token=#{@connection_info.access_token}", body: {"device_keys" => device_keys}.to_json)
    end

    def claim_key(user_id, device_id)
      response = HTTP::Client.post(url: "#{MATRIX_HS}/_matrix/client/unstable/keys/claim?access_token=#{@connection_info.access_token}", body: {"one_time_keys" => {user_id => {device_id => "signed_curve25519"}}}.to_json)
    end

    def upload_keys
      response = HTTP::Client.post(url: "#{MATRIX_HS}/_matrix/client/unstable/keys/upload?access_token=#{@connection_info.access_token}", body: @account.to_json)
    end

    def create_session(event)
      @logger.debug event
      cipher_key = event.content["ciphertext"].as_h.keys.first
      cipher_body = event.content["ciphertext"][cipher_key]["body"].to_s
      cipher_copy1 = String.new(cipher_body.to_slice)
      cipher_copy2 = String.new(cipher_body.to_slice)
      session = Intuit::Session.new
      session.create_inbound_from(@account, event.content["sender_key"].to_s, cipher_copy1)
      decrypted = session.decrypt(0, cipher_copy2)
      session_data = JSON.parse(decrypted)
      @logger.debug decrypted
      # content = JSON.parse(decrypted)
      # @logger.debug content
      inbound_session = Intuit::InboundGroupSession.new(session_data["content"]["session_key"].to_s, session_data["content"]["chain_index"].as_i)
      @sessions[session_data["content"]["room_id"].to_s] = inbound_session
      # @logger.debug inbound_session
    end

    def sync(timestamp = "")
      since = timestamp.empty? ? timestamp : "&since=#{timestamp}"
      response = HTTP::Client.get(url: "#{MATRIX_HS}/_matrix/client/r0/sync?access_token=#{@connection_info.access_token}#{since}")
      sync_data = Sync.from_json(response.body)
      # p sync_data
      sync_data.to_device.events.each do |event|
        # puts event.inspect
        if event.type == "m.room.encrypted"
          create_session(event)
        end
      end
      sync_data.rooms.join.each do |room_id, joined_room|
        puts room_id
        joined_room.timeline.events.each do |event|
          if event.type == "m.room.encrypted" && @sessions[room_id]?
            puts event.content
            puts event.type
            decrypted = @sessions[room_id].decrypt(event.content["ciphertext"].to_s)
            @logger.debug decrypted
          end
        end
      end
      sync(sync_data.next_batch)
      # begin
      #   ciphertext = JSON.parse(response.body)["rooms"]["join"]["!zspysqAuNIRFmUEVNl:matrix.org"]["timeline"]["events"][0]["content"]["ciphertext"]
      #   @logger.debug ciphertext.to_json
      #   if @inbound_session
      #     # @logger.debug "HAVE SESSION"
      #     # @logger.debug "TRying"
      #     @logger.debug @inbound_session.as(Intuit::InboundGroupSession).decrypt(ciphertext.to_s)
      #     # @logger.debug @inbound_session.decrypt( parsed_key.chain_index)
      #     # @logger.debug "WAT"
      #   end
      # rescue e
      # end
      # @logger.debug events.keys
      # @logger.debug next_batch
      # event_json = events["to_device"].to_json
      # @logger.debug event_json
      # events = Hash(String, Array(Event)).from_json(event_json)["events"]
      # @logger.debug events
      # if events.size > 0
      #   content = events.first.content
      #   if content.class == NewSession
      #     create_session(content)
      #   end
      # end
      # @logger.debug @connection_info.device_id
      # @logger.info "Resyncing"
      # sync(next_batch)
    end
  end
end
