# frozen_string_literal: false
require 'socket'
require 'openssl'
require_relative 'drb'
require 'singleton'

module DRb

  # The protocol for DRb over an SSL socket
  #
  # The URI for a DRb socket over SSL is:
  # <code>drbssl://<host>:<port>?<option></code>.  The option is optional
  class DRbSSLSocket < DRbTCPSocket

    # SSLConfig handles the needed SSL information for establishing a
    # DRbSSLSocket connection, including generating the X509 / RSA pair.
    #
    # An instance of this config can be passed to DRbSSLSocket.new,
    # DRbSSLSocket.open and DRbSSLSocket.open_server
    #
    # See DRb::DRbSSLSocket::SSLConfig.new for more details
    class SSLConfig

      # Default values for a SSLConfig instance.
      #
      # See DRb::DRbSSLSocket::SSLConfig.new for more details
      DEFAULT = {
        :SSLCertificate       => nil,
        :SSLPrivateKey        => nil,
        :SSLClientCA          => nil,
        :SSLCACertificatePath => nil,
        :SSLCACertificateFile => nil,
        :SSLTmpDhCallback     => nil,
        :SSLVerifyMode        => ::OpenSSL::SSL::VERIFY_NONE,
        :SSLVerifyDepth       => nil,
        :SSLVerifyCallback    => nil,   # custom verification
        :SSLCertificateStore  => nil,
        # Must specify if you use auto generated certificate.
        :SSLCertName          => nil,   # e.g. [["CN","fqdn.example.com"]]
        :SSLCertComment       => "Generated by Ruby/OpenSSL"
      }

      # Create a new DRb::DRbSSLSocket::SSLConfig instance
      #
      # The DRb::DRbSSLSocket will take either a +config+ Hash or an instance
      # of SSLConfig, and will setup the certificate for its session for the
      # configuration. If want it to generate a generic certificate, the bare
      # minimum is to provide the :SSLCertName
      #
      # === Config options
      #
      # From +config+ Hash:
      #
      # :SSLCertificate ::
      #   An instance of OpenSSL::X509::Certificate.  If this is not provided,
      #   then a generic X509 is generated, with a correspond :SSLPrivateKey
      #
      # :SSLPrivateKey ::
      #   A private key instance, like OpenSSL::PKey::RSA.  This key must be
      #   the key that signed the :SSLCertificate
      #
      # :SSLClientCA ::
      #   An OpenSSL::X509::Certificate, or Array of certificates that will
      #   used as ClientCAs in the SSL Context
      #
      # :SSLCACertificatePath ::
      #   A path to the directory of CA certificates.  The certificates must
      #   be in PEM format.
      #
      # :SSLCACertificateFile ::
      #   A path to a CA certificate file, in PEM format.
      #
      # :SSLTmpDhCallback ::
      #   A DH callback. See OpenSSL::SSL::SSLContext.tmp_dh_callback
      #
      # :SSLMinVersion ::
      #   This is the minimum SSL version to allow.  See
      #   OpenSSL::SSL::SSLContext#min_version=.
      #
      # :SSLMaxVersion ::
      #   This is the maximum SSL version to allow.  See
      #   OpenSSL::SSL::SSLContext#max_version=.
      #
      # :SSLVerifyMode ::
      #   This is the SSL verification mode.  See OpenSSL::SSL::VERIFY_* for
      #   available modes.  The default is OpenSSL::SSL::VERIFY_NONE
      #
      # :SSLVerifyDepth ::
      #   Number of CA certificates to walk, when verifying a certificate
      #   chain.
      #
      # :SSLVerifyCallback ::
      #   A callback to be used for additional verification.  See
      #   OpenSSL::SSL::SSLContext.verify_callback
      #
      # :SSLCertificateStore ::
      #   A OpenSSL::X509::Store used for verification of certificates
      #
      # :SSLCertName ::
      #   Issuer name for the certificate.  This is required when generating
      #   the certificate (if :SSLCertificate and :SSLPrivateKey were not
      #   given).  The value of this is to be an Array of pairs:
      #
      #     [["C", "Raleigh"], ["ST","North Carolina"],
      #      ["CN","fqdn.example.com"]]
      #
      #   See also OpenSSL::X509::Name
      #
      # :SSLCertComment ::
      #   A comment to be used for generating the certificate.  The default is
      #   "Generated by Ruby/OpenSSL"
      #
      #
      # === Example
      #
      # These values can be added after the fact, like a Hash.
      #
      #   require 'drb/ssl'
      #   c = DRb::DRbSSLSocket::SSLConfig.new {}
      #   c[:SSLCertificate] =
      #     OpenSSL::X509::Certificate.new(File.read('mycert.crt'))
      #   c[:SSLPrivateKey] = OpenSSL::PKey::RSA.new(File.read('mycert.key'))
      #   c[:SSLVerifyMode] = OpenSSL::SSL::VERIFY_PEER
      #   c[:SSLCACertificatePath] = "/etc/ssl/certs/"
      #   c.setup_certificate
      #
      # or
      #
      #   require 'drb/ssl'
      #   c = DRb::DRbSSLSocket::SSLConfig.new({
      #           :SSLCertName => [["CN" => DRb::DRbSSLSocket.getservername]]
      #           })
      #   c.setup_certificate
      #
      def initialize(config)
        @config  = config
        @cert    = config[:SSLCertificate]
        @pkey    = config[:SSLPrivateKey]
        @ssl_ctx = nil
      end

      # A convenience method to access the values like a Hash
      def [](key);
        @config[key] || DEFAULT[key]
      end

      # Connect to IO +tcp+, with context of the current certificate
      # configuration
      def connect(tcp)
        ssl = ::OpenSSL::SSL::SSLSocket.new(tcp, @ssl_ctx)
        ssl.sync = true
        ssl.connect
        ssl
      end

      # Accept connection to IO +tcp+, with context of the current certificate
      # configuration
      def accept(tcp)
        ssl = OpenSSL::SSL::SSLSocket.new(tcp, @ssl_ctx)
        ssl.sync = true
        ssl.accept
        ssl
      end

      # Ensures that :SSLCertificate and :SSLPrivateKey have been provided
      # or that a new certificate is generated with the other parameters
      # provided.
      def setup_certificate
        if @cert && @pkey
          return
        end

        rsa = OpenSSL::PKey::RSA.new(2048){|p, n|
          next unless self[:verbose]
          case p
          when 0; $stderr.putc "."  # BN_generate_prime
          when 1; $stderr.putc "+"  # BN_generate_prime
          when 2; $stderr.putc "*"  # searching good prime,
                                    # n = #of try,
                                    # but also data from BN_generate_prime
          when 3; $stderr.putc "\n" # found good prime, n==0 - p, n==1 - q,
                                    # but also data from BN_generate_prime
          else;   $stderr.putc "*"  # BN_generate_prime
          end
        }

        cert = OpenSSL::X509::Certificate.new
        cert.version = 2 # This means v3
        cert.serial = 0
        name = OpenSSL::X509::Name.new(self[:SSLCertName])
        cert.subject = name
        cert.issuer = name
        cert.not_before = Time.now
        cert.not_after = Time.now + (365*24*60*60)
        cert.public_key = rsa.public_key

        ef = OpenSSL::X509::ExtensionFactory.new(nil,cert)
        cert.extensions = [
          ef.create_extension("basicConstraints","CA:FALSE"),
          ef.create_extension("subjectKeyIdentifier", "hash") ]
        ef.issuer_certificate = cert
        cert.add_extension(ef.create_extension("authorityKeyIdentifier",
                                               "keyid:always,issuer:always"))
        if comment = self[:SSLCertComment]
          cert.add_extension(ef.create_extension("nsComment", comment))
        end
        cert.sign(rsa, "SHA256")

        @cert = cert
        @pkey = rsa
      end

      # Establish the OpenSSL::SSL::SSLContext with the configuration
      # parameters provided.
      def setup_ssl_context
        ctx = ::OpenSSL::SSL::SSLContext.new
        ctx.cert            = @cert
        ctx.key             = @pkey
        ctx.min_version     = self[:SSLMinVersion]
        ctx.max_version     = self[:SSLMaxVersion]
        ctx.client_ca       = self[:SSLClientCA]
        ctx.ca_path         = self[:SSLCACertificatePath]
        ctx.ca_file         = self[:SSLCACertificateFile]
        ctx.tmp_dh_callback = self[:SSLTmpDhCallback]
        ctx.verify_mode     = self[:SSLVerifyMode]
        ctx.verify_depth    = self[:SSLVerifyDepth]
        ctx.verify_callback = self[:SSLVerifyCallback]
        ctx.cert_store      = self[:SSLCertificateStore]
        @ssl_ctx = ctx
      end
    end

    # Parse the dRuby +uri+ for an SSL connection.
    #
    # Expects drbssl://...
    #
    # Raises DRbBadScheme or DRbBadURI if +uri+ is not matching or malformed
    def self.parse_uri(uri) # :nodoc:
      if /\Adrbssl:\/\/(.*?):(\d+)(\?(.*))?\z/ =~ uri
        host = $1
        port = $2.to_i
        option = $4
        [host, port, option]
      else
        raise(DRbBadScheme, uri) unless uri.start_with?('drbssl:')
        raise(DRbBadURI, 'can\'t parse uri:' + uri)
      end
    end

    # Return an DRb::DRbSSLSocket instance as a client-side connection,
    # with the SSL connected.  This is called from DRb::start_service or while
    # connecting to a remote object:
    #
    #   DRb.start_service 'drbssl://localhost:0', front, config
    #
    # +uri+ is the URI we are connected to,
    # <code>'drbssl://localhost:0'</code> above, +config+ is our
    # configuration.  Either a Hash or DRb::DRbSSLSocket::SSLConfig
    def self.open(uri, config)
      host, port, = parse_uri(uri)
      soc = TCPSocket.open(host, port)
      ssl_conf = SSLConfig::new(config)
      ssl_conf.setup_ssl_context
      ssl = ssl_conf.connect(soc)
      self.new(uri, ssl, ssl_conf, true)
    end

    # Returns a DRb::DRbSSLSocket instance as a server-side connection, with
    # the SSL connected.  This is called from DRb::start_service or while
    # connecting to a remote object:
    #
    #   DRb.start_service 'drbssl://localhost:0', front, config
    #
    # +uri+ is the URI we are connected to,
    # <code>'drbssl://localhost:0'</code> above, +config+ is our
    # configuration.  Either a Hash or DRb::DRbSSLSocket::SSLConfig
    def self.open_server(uri, config)
      uri = 'drbssl://:0' unless uri
      host, port, = parse_uri(uri)
      if host.size == 0
        host = getservername
        soc = open_server_inaddr_any(host, port)
      else
        soc = TCPServer.open(host, port)
      end
      port = soc.addr[1] if port == 0
      @uri = "drbssl://#{host}:#{port}"

      ssl_conf = SSLConfig.new(config)
      ssl_conf.setup_certificate
      ssl_conf.setup_ssl_context
      self.new(@uri, soc, ssl_conf, false)
    end

    # This is a convenience method to parse +uri+ and separate out any
    # additional options appended in the +uri+.
    #
    # Returns an option-less uri and the option => [uri,option]
    #
    # The +config+ is completely unused, so passing nil is sufficient.
    def self.uri_option(uri, config) # :nodoc:
      host, port, option = parse_uri(uri)
      return "drbssl://#{host}:#{port}", option
    end

    # Create a DRb::DRbSSLSocket instance.
    #
    # +uri+ is the URI we are connected to.
    # +soc+ is the tcp socket we are bound to.
    # +config+ is our configuration. Either a Hash or SSLConfig
    # +is_established+ is a boolean of whether +soc+ is currently established
    #
    # This is called automatically based on the DRb protocol.
    def initialize(uri, soc, config, is_established)
      @ssl = is_established ? soc : nil
      super(uri, soc.to_io, config)
    end

    # Returns the SSL stream
    def stream; @ssl; end # :nodoc:

    # Closes the SSL stream before closing the dRuby connection.
    def close # :nodoc:
      if @ssl
        @ssl.close
        @ssl = nil
      end
      super
    end

    def accept # :nodoc:
      begin
      while true
        soc = accept_or_shutdown
        return nil unless soc
        break if (@acl ? @acl.allow_socket?(soc) : true)
        soc.close
      end
      begin
        ssl = @config.accept(soc)
      rescue Exception
        soc.close
        raise
      end
      self.class.new(uri, ssl, @config, true)
      rescue OpenSSL::SSL::SSLError
        warn("#{$!.message} (#{$!.class})", uplevel: 0) if @config[:verbose]
        retry
      end
    end
  end

  DRbProtocol.add_protocol(DRbSSLSocket)
end
