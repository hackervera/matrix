require "json"

module Matrix
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
end
