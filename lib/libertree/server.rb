require 'eventmachine'
require 'json'
require 'socket'
require 'gpgme'

require 'libertree/authenticatable'
require 'libertree/model'
require 'libertree/server/responder'

module Libertree
  module Server
    PORT = 14404

    class << self
      attr_accessor :conf
    end

    include Responder

    # EventMachine callbacks

    def post_init
      port, @ip_remote = Socket.unpack_sockaddr_in(get_peername)
      puts "#{@ip_remote} connected."
    end

    def receive_data(data)
      process data
    end

    def unbind
      puts "#{@ip_remote} disconnected."
      if @server
        @server.challenge = nil
        @server = nil
      end
    end

    # -------

    def introduced?
      @server && @server.public_key
    end

    def self.load_config(config_filename)
      @conf = YAML.load( File.read(config_filename) )
      [
      ].each do |required_key|
        if @conf[required_key].nil?
          raise "Configuration error: #{required_key} is required."
        end
      end
    end

    def self.run(config_filename)
      load_config config_filename
      EventMachine.run do
        EventMachine.start_server '127.0.0.1', PORT, self
        puts "Libertree started."
        puts "Listening on port #{PORT}."
      end
    end
  end
end
