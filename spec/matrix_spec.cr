require "./spec_helper"

describe Matrix::Client do
  describe "#initialize" do
    it "logs into matrix and returns an instance to call api methods on" do
      client = Matrix::Client.new
      client.connection_info.user_id.should eq "@#{client.user}:#{client.matrix_host}"
    end
  end
  describe "#sync" do
    it "grabs the intial sync data from matrix home server" do
      client = Matrix::Client.new
      client.logger.level = Logger::DEBUG
      # spawn { client.sync }
      # sleep
      # puts client.connection_info.inspect
      # client.upload_keys
      # puts client.device_list(["@kodotest:matrix.org"]).body
      # client.send_devices(["@kodo:matrix.org", "@kodotest:matrix.org"], ["!uDdaWrPIMfVSmfaekz:matrix.org"])
      # client.sync
      begin
        next_batch = File.read("next-batch")
        client.sync(next_batch)
      rescue
        client.sync
      end
    end
  end
  describe "#claim_key" do
    it "Claims one-time keys for use in pre-key messages." do
      client = Matrix::Client.new
      client.logger.level = Logger::DEBUG
      # client.connection_info.inspect
      client.upload_keys
      # puts client.device_list(["@kodotest:matrix.org"]).body
      client.send_devices(["@kodo:matrix.org", "@kodotest:matrix.org"], ["!zspysqAuNIRFmUEVNl:matrix.org"])
      # puts client.claim_key(client.connection_info.user_id, client.connection_info.device_id).body
      begin
        next_batch = File.read("next-batch")
        client.sync(next_batch)
      rescue
        client.sync
      end
    end
  end
end
