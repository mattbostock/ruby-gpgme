module GPGME

  ##
  # Different, independent methods providing the simplest possible API to
  # execute crypto operations via GPG. All methods accept as options the same
  # common options as {GPGME::Ctx.new}. Read the documentation for that class to
  # know how to customize things further (like output stuff in ASCII armored
  # format, for example).
  module Crypto
    class << self

      ##
      # Encrypts an element
      #
      #  GPGME::Crypto.encrypt something, options
      #
      # Will return a {GPGME::Data} element which can then be read.
      #
      # Must have some key imported, look for {.import} to know how
      # to import one, or the gpg documentation to know how to create one
      #
      # @param plain
      #  Must be something that can be converted into a {GPGME::Data} object, or
      #  a {GPGME::Data} object itself.
      #
      # @param [Hash] options
      #  The optional parameters are as follows:
      #  * +:recipients+ for which recipient do you want to encrypt this file. It
      #    will pick the first one available if none specified. Can be an array of
      #    identifiers or just one (a string).
      #  * +:always_trust+ if set to true specifies all the recipients to be
      #    trusted, thus not requiring confirmation.
      #  * +:sign+ if set to true, performs a combined sign and encrypt operation.
      #  * +:signers+ if +:sign+ specified to true, a list of additional possible
      #    signers. Must be an array of sign identifiers.
      #  * +:output+ if specified, it will write the output into it. It will be
      #    converted to a {GPGME::Data} object, so it could be a file for example.
      #   * Any other option accepted by {GPGME::Ctx.new}
      #
      # @return [GPGME::Data] a {GPGME::Data} object that can be read.
      #
      # @example returns a {GPGME::Data} that can be later encrypted
      #  encrypted = GPGME::Crypto.encrypt "Hello world!"
      #  encrypted.read # => Encrypted stuff
      #
      # @example to be decrypted by someone@example.com.
      #  GPGME::Crypto.encrypt "Hello", :recipients => "someone@example.com"
      #
      # @example If I didn't trust any of my keys by default
      #  GPGME::Crypto.encrypt "Hello" # => GPGME::Error::General
      #  GPGME::Crypto.encrypt "Hello", :always_trust => true # => Will work fine
      #
      # @example encrypted string that can be decrypted and/or *verified*
      #  GPGME::Crypto.encrypt "Hello", :sign => true
      #
      # @example multiple signers
      #  GPGME::Crypto.encrypt "Hello", :sign => true, :signers => "extra@example.com"
      #
      # @example writing to a file instead
      #  file = File.open("signed.sec","w+")
      #  GPGME::Crypto.encrypt "Hello", :output => file # output written to signed.sec
      #
      # @raise [GPGME::Error::General] when trying to encrypt with a key that is
      #   not trusted, and +:always_trust+ wasn't specified
      #
      def encrypt(plain, options = {})
        plain_data  = Data.new(plain)
        cipher_data = Data.new(options[:output])
        keys        = Key.find(:public, options[:recipients])

        flags = 0
        flags |= GPGME::ENCRYPT_ALWAYS_TRUST if options[:always_trust]

        GPGME::Ctx.new(options) do |ctx|
          begin
            if options[:sign]
              if options[:signers]
                signers = Key.find(:public, options[:signers], :sign)
                ctx.add_signer(*signers)
              end
              ctx.encrypt_sign(keys, plain_data, cipher_data, flags)
            else
              ctx.encrypt(keys, plain_data, cipher_data, flags)
            end
          rescue GPGME::Error::UnusablePublicKey => exc
            exc.keys = ctx.encrypt_result.invalid_recipients
            raise exc
          rescue GPGME::Error::UnusableSecretKey => exc
            exc.keys = ctx.sign_result.invalid_signers
            raise exc
          end
        end

        cipher_data.seek(0)
        cipher_data
      end

      ##
      # Decrypts a previously encrypted element
      #
      #   GPGME::Crypto.decrypt cipher, options, &block
      #
      # Must have the appropiate key to be able to decrypt, of course. Returns
      # a {GPGME::Data} object which can then be read.
      #
      # @param cipher
      #   Must be something that can be converted into a {GPGME::Data} object,
      #   or a {GPGME::Data} object itself. It is the element that will be
      #   decrypted.
      #
      # @param [Hash] options
      #   The optional parameters:
      #   * +:output+ if specified, it will write the output into it. It will
      #     me converted to a {GPGME::Data} object, so it can also be a file,
      #     for example.
      #   * Any other option accepted by {GPGME::Ctx.new}
      #
      # @param &block
      #   In the block all the signatures are yielded, so one could verify them.
      #   See examples.
      #
      # @return [GPGME::Data] a {GPGME::Data} that can be read.
      #
      # @example Simple decrypt
      #   GPGME::Crypto.decrypt encrypted_data
      #
      # @example Output to file
      #   file = File.open("decrypted.txt", "w+")
      #   GPGME::Crypto.decrypt encrypted_data, :output => file
      #
      # @example Verifying signatures
      #   GPGME::Crypto.decrypt encrypted_data do |signature|
      #     raise "Signature could not be verified" unless signature.valid?
      #   end
      #
      # @raise [GPGME::Error::UnsupportedAlgorithm] when the cipher was encrypted
      #   using an algorithm that's not supported currently.
      #
      # @raise [GPGME::Error::WrongKeyUsage] TODO Don't know when
      #
      # @raise [GPGME::Error::DecryptFailed] when the cipher was encrypted
      #   for a key that's not available currently.
      def decrypt(cipher, options = {})
        plain_data   = Data.new(options[:output])
        cipher_data  = Data.new(cipher)

        GPGME::Ctx.new(options) do |ctx|
          begin
            ctx.decrypt_verify(cipher_data, plain_data)
          rescue GPGME::Error::UnsupportedAlgorithm => exc
            exc.algorithm = ctx.decrypt_result.unsupported_algorithm
            raise exc
          rescue GPGME::Error::WrongKeyUsage => exc
            exc.key_usage = ctx.decrypt_result.wrong_key_usage
            raise exc
          end

          verify_result = ctx.verify_result
          if verify_result && block_given?
            verify_result.signatures.each do |signature|
              yield signature
            end
          end

        end

        plain_data.seek(0)
        plain_data
      end

      ##
      # Creates a signature of a text
      #
      #   GPGME::Crypto.sign text, options
      #
      # Must have the appropiate key to be able to decrypt, of course. Returns
      # a {GPGME::Data} object which can then be read.
      #
      # @param text
      #   The object that will be signed. Must be something that can be converted
      #   to {GPGME::Data}.
      #
      # @param [Hash] options
      #  Optional parameters.
      #   * +:signer+ sign identifier to sign the text with. Will use the first
      #    key it finds if none specified.
      #   * +:output+ if specified, it will write the output into it. It will be
      #     converted to a {GPGME::Data} object, so it could be a file for example.
      #   * +:mode+ Desired type of signature. Options are:
      #    - +GPGME::SIG_MODE_NORMAL+ for a normal signature. The default one if
      #      not specified.
      #    - +GPGME::SIG_MODE_DETACH+ for a detached signature
      #    - +GPGME::SIG_MODE_CLEAR+ for a cleartext signature
      #   * Any other option accepted by {GPGME::Ctx.new}
      #
      # @return [GPGME::Data] a {GPGME::Data} that can be read.
      #
      # @example normal sign
      #   GPGME::Crypto.sign "Hi there"
      #
      # @example outputing to a file
      #   file = File.open("text.sign", "w+")
      #   GPGME::Crypto.sign "Hi there", :options => file
      #
      # @example doing a detached signature
      #   GPGME::Crypto.sign "Hi there", :mode => GPGME::SIG_MODE_DETACH
      #
      # @example specifying the signer
      #   GPGME::Crypto.sign "Hi there", :signer => "mrsimo@example.com"
      #
      # @raise [GPGME::Error::UnusableSecretKey] TODO don't know
      def sign(text, options = {})
        plain  = Data.new(text)
        output = Data.new(options[:output])
        mode   = options[:mode] || GPGME::SIG_MODE_NORMAL

        GPGME::Ctx.new(options) do |ctx|
          if options[:signer]
            signers = Key.find(:secret, options[:signer], :sign)
            ctx.add_signer(*signers)
          end

          begin
            ctx.sign(plain, output, mode)
          rescue GPGME::Error::UnusableSecretKey => exc
            exc.keys = ctx.sign_result.invalid_signers
            raise exc
          end
        end

        output.seek(0)
        output
      end

      # Verifies a previously signed element
      #
      #   GPGME::Crypto.verify sig, options, &block
      #
      # Must have the proper keys available.
      #
      # @param sig
      #   The signature itself. Must be possible to convert into a {GPGME::Data}
      #   object, so can be a file.
      #
      # @param [Hash] options
      #   * +:signed_text+ if the sign is detached, then must be the plain text
      #     for which the signature was created.
      #   * +:output+ where to store the result of the signature. Will be
      #     converted to a {GPGME::Data} object.
      #   * Any other option accepted by {GPGME::Ctx.new}
      #
      # @param &block
      #   In the block all the signatures are yielded, so one could verify them.
      #   See examples.
      #
      # @return [GPGME::Data] unless the sign is detached, the {GPGME::Data}
      #   object with the plain text. If the sign is detached, will return nil.
      #
      # @example simple verification
      #   sign = GPGME::Crypto.sign("Hi there")
      #   data = GPGME::Crypto.verify(sign) { |signature| signature.valid? }
      #   data.read # => "Hi there"
      #
      # @example saving output to file
      #   sign = GPGME::Crypto.sign("Hi there")
      #   out  = File.open("test.asc", "w+")
      #   GPGME::Crypto.verify(sign, :output => out) {|signature| signature.valid?}
      #   out.read # => "Hi there"
      #
      # @example verifying a detached signature
      #   sign = GPGME::Crypto.detach_sign("Hi there")
      #   # Will fail
      #   GPGME::Crypto.verify(sign) { |signature| signature.valid? }
      #   # Will succeed
      #   GPGME::Crypto.verify(sign, :signed_text => "hi there") do |signature|
      #     signature.valid?
      #   end
      #
      def verify(sig, options = {}) # :yields: signature
        sig         = Data.new(sig)
        signed_text = Data.new(options[:signed_text])
        output      = Data.new(options[:output]) unless options[:signed_text]

        GPGME::Ctx.new(options) do |ctx|
          ctx.verify(sig, signed_text, output)
          ctx.verify_result.signatures.each do |signature|
            yield signature
          end
        end

        if output
          output.seek(0)
          output
        end
      end

      # Clearsigns an element
      #
      #   GPGME::Crypto.clearsign text, options
      #
      # Same functionality of {.sign} only doing clearsigns by default.
      #
      def clearsign(text, options = {})
        sign text, options.merge(:mode => GPGME::SIG_MODE_CLEAR)
      end

      # Creates a detached signature of an element
      #
      #   GPGME::Crypto.detach_sign text, options
      #
      # Same functionality of {.sign} only doing detached signs by default.
      #
      def detach_sign(text, options = {})
        sign text, options.merge(:mode => GPGME::SIG_MODE_DETACH)
      end

    end # class << self
  end # module Crypto
end # module GPGME