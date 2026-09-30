# frozen_string_literal: false
require_relative 'drbtest'

begin
  require 'drb/ssl'
rescue LoadError
end

module DRbTests

if Object.const_defined?("OpenSSL")


class DRbSSLService < DRbService
  %w(ut_drb_drbssl.rb ut_array_drbssl.rb).each do |nm|
    add_service_command(nm)
  end

  def start
    config = Hash.new

    config[:SSLVerifyMode] = OpenSSL::SSL::VERIFY_PEER
    config[:SSLVerifyCallback] = lambda{ |ok,x509_store|
      true
    }
    if RUBY_PLATFORM.match?(/openbsd/)
      config[:SSLMinVersion] = OpenSSL::SSL::TLS1_2_VERSION
      config[:SSLMaxVersion] = OpenSSL::SSL::TLS1_2_VERSION
    end
    begin
      data = open("sample.key"){|io| io.read }
      config[:SSLPrivateKey] = OpenSSL::PKey::RSA.new(data)
      data = open("sample.crt"){|io| io.read }
      config[:SSLCertificate] = OpenSSL::X509::Certificate.new(data)
    rescue
      # $stderr.puts "Switching to use self-signed certificate"
      config[:SSLCertName] =
        [ ["C","JP"], ["O","Foo.DRuby.Org"], ["CN", "Sample"] ]
    end

    @server = DRb::DRbServer.new('drbssl://localhost:0', manager, config)
  end
end

class TestDRbSSLCore < Test::Unit::TestCase
  include DRbCore
  def setup
    if RUBY_PLATFORM.match?(/mswin|mingw/)
      @omitted = true
      omit 'This test seems to randomly hang on Windows'
    end
    @drb_service = DRbSSLService.new
    super
    setup_service 'ut_drb_drbssl.rb'
  end

  def test_02_unknown
  end

  def test_01_02_loop
  end

  def test_05_eq
  end
end

class TestDRbSSLAry < Test::Unit::TestCase
  include DRbAry
  def setup
    if RUBY_PLATFORM.match?(/mswin|mingw/)
      @omitted = true
      omit 'This test seems to randomly hang on Windows'
    end
    LeakChecker.skip if defined?(LeakChecker)
    @drb_service = DRbSSLService.new
    super
    setup_service 'ut_array_drbssl.rb'
  end
end


class TestDRbSSLContext < Test::Unit::TestCase
  def setup
    if RUBY_PLATFORM.match?(/mswin|mingw/)
      omit 'This test seems to randomly hang on Windows'
    end
    @cert, key = generate_certificate
    server_ctx = OpenSSL::SSL::SSLContext.new
    server_ctx.add_certificate(@cert, key)
    @server = DRb::DRbServer.new('drbssl://localhost:0', nil,
                                 {SSLContext: server_ctx})
    begin
      yield
    ensure
      @server.stop_service
    end
  end

  def test_ssl_context
    ctx = OpenSSL::SSL::SSLContext.new
    client = DRb::DRbSSLSocket.open(@server.uri, {SSLContext: ctx})
    begin
      assert_equal([ctx, @cert.to_der],
                   [client.stream.context, client.stream.peer_cert.to_der])
    ensure
      client.close
    end
  end

  def test_basic_ssl_config
    ctx = OpenSSL::SSL::SSLContext.new
    config = DRb::DRbSSLSocket::BasicSSLConfig.new({}, ctx)
    client = DRb::DRbSSLSocket.open(@server.uri, config)
    begin
      assert_same(ctx, client.stream.context)
    ensure
      client.close
    end
  end

  private
  def generate_certificate
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    name = OpenSSL::X509::Name.new([["CN", "localhost"]])
    cert.subject = name
    cert.issuer = name
    cert.not_before = Time.now
    cert.not_after = Time.now + 3600
    cert.public_key = key
    cert.sign(key, "SHA256")
    [cert, key]
  end
end

end

end
