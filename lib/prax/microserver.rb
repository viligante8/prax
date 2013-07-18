require 'socket'
require 'thread'
require 'prax/ssl'

module Prax
  class MicroServer
    attr_reader :listeners, :thread

    def initialize
      @pipe = IO.pipe
      @mutex = Mutex.new
      @listeners = []
    end

    def add_tcp_listener(host, port = nil)
      add TCPServer.new(*[host, port].compact)
    end

    def add_ssl_listener(host, port = nil)
      return unless ssl_configured?
      add OpenSSL::SSL::SSLServer.new(TCPServer.new(*[host, port].compact), ssl_context)
    end

    def add_unix_listener(path)
      add UNIXServer.new(path)
    end

    def run
      @thread = Thread.new { select until @_stopping }
    end

    def serve(socket, ssl)
    end

    def stop(sync = false)
      @_stopping = true
      @pipe.last.write_nonblock('.')

      if @thread
        @thread.join if sync
      else
        finalize
      end
    end

    def finalize
      @mutex.synchronize do
        listeners.pop.tap do |listener|
          if listener.respond_to?(:path) and File.exists?(listener.path)
            File.unlink(listener.path)
          end
          listener.close rescue nil
        end until listeners.empty?
      end
    end

    def started?
      listeners.any? and !@_stopping
    end

    protected
      def select
        IO.select(listeners + [@pipe.first]).first.each do |io|
          if io == @pipe.first
            handle_signal
            break
          end
          if socket = io.accept_nonblock
            serve(socket, socket.is_a?(OpenSSL::SSL::SSLServer))
          end
        end
      end

      def handle_signal
        @pipe.first.read_nonblock(1)
        finalize
      end

      def add(listener)
        @mutex.synchronize { listeners << listener }
      end

      def ssl_context
        OpenSSL::SSL::SSLContext.new.tap do |ctx|
          ctx.cert = OpenSSL::X509::Certificate.new(File.read(@ssl_crt))
          ctx.key  = OpenSSL::PKey::RSA.new(File.read(@ssl_key))
        end
      end

      def ssl_configured?
        @ssl_crt and File.exists?(@ssl_crt) and @ssl_key and File.exists?(@ssl_key)
      end
  end
end